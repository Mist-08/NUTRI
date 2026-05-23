"""
Cliente de Gemini con manejo robusto de errores y fallback silencioso.

Filosofía de diseño:
- Si Gemini no está disponible (sin key, sin paquete, sin internet, sin cuota),
  los métodos devuelven None y el caller usa su lógica de respaldo.
- Reintentos exponenciales para errores 429 (rate limit).
- Saneamiento de JSON cuando Gemini devuelve markdown o texto truncado.
- Una sola instancia compartida por proceso (singleton lazy).

Nota: el timeout NO se configura aquí (el SDK tiene bugs conocidos con eso).
El caller que necesite timeout debe envolver la llamada con
concurrent.futures.ThreadPoolExecutor + future.result(timeout=N).
"""

import os
import json
import logging
import re
import time
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

# Soft import: si google-genai no está instalado, el cliente queda no disponible
# en vez de tronar el arranque del backend.
try:
    from google import genai
    from google.genai import types
    _GENAI_AVAILABLE = True
except ImportError:
    _GENAI_AVAILABLE = False
    logger.warning(
        "Paquete google-genai no instalado. "
        "Las funciones de IA estarán deshabilitadas. "
        "Instálalo con: pip install google-genai"
    )


class GeminiClient:
    """Wrapper sobre google-genai con retry y fallback silencioso."""

    DEFAULT_MODEL = "gemini-2.5-flash"
    MAX_RETRIES = 2
    RETRY_BASE_DELAY = 1.0  # segundos, se duplica en cada intento

    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self.model_name = os.getenv("GEMINI_MODEL", self.DEFAULT_MODEL)
        self._client = None
        self.available: bool = False

        if not _GENAI_AVAILABLE:
            return

        if not self.api_key:
            logger.warning(
                "GEMINI_API_KEY no configurada en .env. "
                "Las funciones de IA estarán deshabilitadas."
            )
            return

        try:
            self._client = genai.Client(api_key=self.api_key)
            self.available = True
            logger.info("Gemini client inicializado (modelo=%s)", self.model_name)
        except Exception as e:
            logger.warning("No se pudo inicializar Gemini: %s", e)

    # ── Generación de texto ───────────────────────────────────────────

    def generate(
        self,
        prompt: str,
        system: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        json_mode: bool = False,
    ) -> Optional[str]:
        """
        Genera una respuesta con Gemini. Devuelve el texto o None si falla.

        Args:
            prompt:      el mensaje del usuario
            system:      instrucciones de sistema (rol, tono, formato)
            temperature: 0.0 = determinístico, 1.0 = creativo
            max_tokens:  límite de longitud de la respuesta
            json_mode:   si True, fuerza salida JSON parseable
        """
        if not self.available:
            return None

        config_kwargs: Dict[str, Any] = {
            "temperature": temperature,
            "max_output_tokens": max_tokens,
        }
        if system:
            config_kwargs["system_instruction"] = system
        if json_mode:
            config_kwargs["response_mime_type"] = "application/json"

        for attempt in range(self.MAX_RETRIES + 1):
            try:
                response = self._client.models.generate_content(
                    model=self.model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(**config_kwargs),
                )
                text = (response.text or "").strip()
                if not text:
                    logger.warning("Gemini devolvió respuesta vacía")
                    return None
                return text

            except Exception as e:
                err_str = str(e).lower()
                is_rate_limit = (
                    "429" in err_str
                    or "quota" in err_str
                    or "rate" in err_str
                    or "resource" in err_str  # google a veces dice RESOURCE_EXHAUSTED
                )

                if is_rate_limit and attempt < self.MAX_RETRIES:
                    delay = self.RETRY_BASE_DELAY * (2 ** attempt)
                    logger.info(
                        "Gemini rate-limited (intento %d/%d); reintento en %.1fs",
                        attempt + 1, self.MAX_RETRIES + 1, delay,
                    )
                    time.sleep(delay)
                    continue

                logger.warning(
                    "Gemini error (intento %d/%d): %s",
                    attempt + 1, self.MAX_RETRIES + 1, e,
                )
                return None

        return None

    # ── Generación de JSON estructurado ───────────────────────────────

    def generate_json(
        self,
        prompt: str,
        system: Optional[str] = None,
        temperature: float = 0.3,
        max_tokens: int = 2048,
    ) -> Optional[Dict[str, Any]]:
        """
        Genera y parsea JSON. Devuelve None si falla en cualquier paso
        (generación, parseo o JSON inválido).

        max_tokens por defecto sube a 2048 porque las respuestas JSON con
        varios campos (reply + suggestions + ids) pueden truncarse a la
        mitad si es muy bajo, dejando JSON inválido.
        """
        text = self.generate(
            prompt=prompt,
            system=system,
            temperature=temperature,
            max_tokens=max_tokens,
            json_mode=True,
        )
        if not text:
            return None

        # Limpieza: a veces Gemini añade ```json ... ``` aunque pidamos JSON puro
        text = _strip_json_fence(text)

        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            # Intento de rescate: extraer el primer objeto JSON balanceado
            recovered = _try_extract_json_object(text)
            if recovered is not None:
                logger.info(
                    "Gemini JSON recuperado tras parse error: %s",
                    str(e)[:100],
                )
                return recovered

            logger.warning(
                "Gemini JSON parse error: %s | text[:300]=%r",
                e, text[:300],
            )
            return None


# ── Saneamiento de JSON ───────────────────────────────────────────────

_JSON_FENCE_RE = re.compile(
    r"^```(?:json)?\s*(.*?)\s*```$",
    re.DOTALL | re.IGNORECASE,
)


def _strip_json_fence(text: str) -> str:
    """Quita los ```json ... ``` que a veces aparecen aunque pidamos JSON puro."""
    text = text.strip()
    m = _JSON_FENCE_RE.match(text)
    if m:
        return m.group(1).strip()
    return text


def _try_extract_json_object(text: str) -> Optional[Dict[str, Any]]:
    """
    Si Gemini devolvió texto con un JSON embebido o se cortó a media frase,
    intenta extraer el primer objeto JSON balanceado y parsearlo.
    Devuelve None si no se puede recuperar.
    """
    start = text.find("{")
    if start == -1:
        return None

    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                candidate = text[start:i + 1]
                try:
                    return json.loads(candidate)
                except json.JSONDecodeError:
                    return None
    return None


# ── Singleton lazy ────────────────────────────────────────────────────

_singleton: Optional[GeminiClient] = None


def get_gemini_client() -> GeminiClient:
    """Devuelve el cliente Gemini compartido (lazy init en el primer uso)."""
    global _singleton
    if _singleton is None:
        _singleton = GeminiClient()
    return _singleton
