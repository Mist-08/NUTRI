"""
Chatbot conversacional impulsado por Gemini (Fase 4).

A diferencia del chatbot_service viejo (que es un dispatcher con ~30
handlers por intent), este módulo le pasa a Gemini el contexto completo
del usuario y deja que la IA responda libre. Eso permite preguntas
abiertas como "tengo hambre pero tengo que correr, dame algo rápido alto
en proteína" — algo que las reglas no podían manejar.

Cuando Gemini no está disponible, falla o tarda demasiado, el caller cae
al chatbot_service viejo. Esta capa NUNCA inventa alimentos: solo
razona sobre el catálogo, el perfil y el menú del día reales.
"""

import logging
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from datetime import date
from typing import Optional

from sqlalchemy.orm import Session

import models
from services.gemini_client import get_gemini_client

logger = logging.getLogger(__name__)

# Tiempo máximo para que el chatbot responda con Gemini (segundos).
# Si Gemini se cuelga más de esto, caemos al fallback rule-based para no
# dejar al usuario esperando.
CHATBOT_TIMEOUT = 15.0


# ══════════════════════════════════════════════════════════════════════
#  RESPUESTA DEL CHATBOT
# ══════════════════════════════════════════════════════════════════════

def respond_with_gemini(
    db: Session,
    user_message: str,
    ctx: dict,
    historial: Optional[list[dict]] = None,
) -> Optional[dict]:
    """
    Genera una respuesta del chatbot usando Gemini con el contexto del usuario.

    Args:
        db:           sesión activa de SQLAlchemy (para consultar alimentos)
        user_message: el mensaje del usuario
        ctx:          dict construido por chatbot_context_builder.build_context
        historial:    lista [{rol, texto}] de mensajes previos de ESTE usuario,
                      en orden cronológico, para darle memoria a la conversación.

    Returns:
        Dict con shape de schemas.ChatbotResponse, o None si Gemini falla
        o tarda más de CHATBOT_TIMEOUT segundos. El caller debe usar el
        fallback rule-based cuando esto devuelva None.
    """
    try:
        with ThreadPoolExecutor(max_workers=1, thread_name_prefix="gemini-chat") as ex:
            future = ex.submit(_respond_with_gemini_blocking, db, user_message, ctx, historial)
            return future.result(timeout=CHATBOT_TIMEOUT)
    except FuturesTimeout:
        logger.warning(
            "Chatbot Gemini timeout (>%.0fs); usando fallback rule-based",
            CHATBOT_TIMEOUT,
        )
        return None
    except Exception as e:
        logger.warning("Chatbot Gemini error: %s", e)
        return None


def _respond_with_gemini_blocking(
    db: Session,
    user_message: str,
    ctx: dict,
    historial: Optional[list[dict]] = None,
) -> Optional[dict]:
    """Implementación bloqueante (llamada desde el hilo del executor)."""
    client = get_gemini_client()
    if not client.available:
        return None

    # Si no hay perfil, contestamos algo directo sin gastar tokens.
    if not ctx.get("tiene_perfil"):
        return {
            "reply": (
                "Para darte recomendaciones personalizadas primero necesito que "
                "completes tu perfil nutricional (edad, peso, objetivo y dieta). "
                "Lo configuras desde la pantalla de perfil del menú principal."
            ),
            "intent": "sin_perfil",
            "suggestions": [
                "¿Cómo configuro mi perfil?",
                "¿Qué datos necesitas de mí?",
            ],
            "related_menu": None,
            "context_card": None,
        }

    # Construir el contexto compacto para el prompt
    prompt_context = _build_prompt_context(db, ctx)

    # Memoria conversacional: los últimos mensajes de ESTE usuario, para que
    # el bot entienda seguimientos ("¿y eso cuántas calorías tiene?").
    conversacion = _format_historial(historial)

    system_prompt = _SYSTEM_PROMPT
    user_prompt = f"""CONTEXTO DEL USUARIO:
{prompt_context}
{conversacion}
MENSAJE DEL USUARIO:
"{user_message}"

Responde en JSON estricto con esta estructura exacta (sin markdown, sin ```):
{{
  "reply": "<respuesta conversacional en español, máximo 4 frases>",
  "intent": "<una de: que_comer_hoy, snack_estudio, consulta_nutricion, consulta_presupuesto, consulta_perfil, consulta_examen, motivacion, otro>",
  "suggestions": ["<sugerencia 1>", "<sugerencia 2>", "<sugerencia 3>"],
  "sugiere_alimentos": [<lista de IDs de alimentos del catálogo si recomendaste alguno específico, o []>]
}}"""

    result = client.generate_json(
        prompt=user_prompt,
        system=system_prompt,
        temperature=0.7,
        max_tokens=1500,
    )

    if not result:
        return None

    reply = (result.get("reply") or "").strip()
    if not reply or len(reply) < 5:
        logger.warning("Chatbot Gemini devolvió reply vacío o muy corto: %r", reply)
        return None

    # Recuperar alimentos sugeridos para el context_card (si Gemini los citó)
    sugeridos_ids = result.get("sugiere_alimentos", [])
    if not isinstance(sugeridos_ids, list):
        sugeridos_ids = []
    context_card = _build_alimentos_card(db, sugeridos_ids) if sugeridos_ids else None

    # related_menu: si el usuario pregunta por el menú de hoy, lo adjuntamos
    intent = (result.get("intent") or "otro").strip()
    related_menu = None
    if intent in ("que_comer_hoy", "consulta_examen") and ctx.get("menu_hoy"):
        related_menu = _menu_card_from_ctx(ctx["menu_hoy"])

    suggestions = result.get("suggestions") or []
    if not isinstance(suggestions, list):
        suggestions = []
    suggestions = [str(s).strip() for s in suggestions if str(s).strip()][:4]

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": suggestions or _DEFAULT_SUGGESTIONS,
        "related_menu": related_menu,
        "context_card": context_card,
    }


# ══════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════

_SYSTEM_PROMPT = (
    "Eres el Asistente NutriCampus, un chatbot nutricional para estudiantes "
    "universitarios mexicanos. Tu rol:\n"
    "- Das consejos prácticos, breves y cálidos, tuteando al usuario.\n"
    "- Usas el contexto del usuario (perfil, menú de hoy, eventos, presupuesto) "
    "para que tus respuestas sean ÚTILES, no genéricas.\n"
    "- Si el usuario pide alimentos específicos, eliges del catálogo dado por su "
    "id; NUNCA inventas alimentos, calorías ni precios.\n"
    "- Si no hay datos suficientes, lo dices con honestidad.\n"
    "- Mexicanizas referencias gastronómicas (tortilla, frijoles, chilaquiles, etc.).\n"
    "- Sin emojis. Máximo 4 frases por respuesta. Respondes SIEMPRE en JSON estricto.\n"
    "- Si el mensaje del usuario es saludo, salúdalo brevemente y pregunta en qué ayudas.\n"
    "- Si el mensaje es ambiguo, pides una aclaración con una pregunta corta."
)

_DEFAULT_SUGGESTIONS = [
    "¿Qué debería comer hoy?",
    "Dame snacks para estudiar",
    "¿Cómo está mi presupuesto?",
]


def _format_historial(historial: Optional[list[dict]]) -> str:
    """
    Formatea la conversación previa para el prompt. Excluye el mensaje actual
    (que se manda aparte) y omite el saludo inicial del bot si fuera el único.
    Devuelve "" si no hay historial relevante.
    """
    if not historial:
        return ""
    lineas = []
    for m in historial:
        rol = "Usuario" if m.get("rol") == "user" else "Asistente"
        texto = (m.get("texto") or "").strip()
        if texto:
            lineas.append(f"  {rol}: {texto}")
    if not lineas:
        return ""
    return "\nCONVERSACIÓN PREVIA (para mantener contexto):\n" + "\n".join(lineas) + "\n"


def _build_prompt_context(db: Session, ctx: dict) -> str:
    """Compone un bloque de texto compacto con el contexto del usuario para Gemini."""
    lines = []
    lines.append(f"Fecha hoy: {ctx.get('fecha_hoy', '?')} ({ctx.get('dia_semana', '?')})")

    perfil = ctx.get("perfil") or {}
    if perfil:
        lines.append("Perfil:")
        lines.append(f"  - Objetivo: {perfil.get('objetivo', '?')}")
        lines.append(f"  - Dieta: {perfil.get('dieta', '?')}")
        if perfil.get("alergias"):
            lines.append(f"  - Alergias: {perfil['alergias']}")
        if perfil.get("condiciones_medicas"):
            lines.append(f"  - Condiciones médicas: {perfil['condiciones_medicas']}")
        if perfil.get("calorias_diarias"):
            lines.append(f"  - Calorías diarias objetivo: {perfil['calorias_diarias']} kcal")
        ppto = perfil.get("presupuesto_diario")
        if ppto:
            lines.append(
                f"  - Presupuesto diario: ${ppto:.0f} MXN "
                f"(nivel: {perfil.get('nivel_presupuesto', '?')}, "
                f"prefiere: {perfil.get('tipo_menu_preferido', '?')})"
            )

    menu_hoy = ctx.get("menu_hoy")
    if menu_hoy:
        lines.append("Menú de hoy (ya generado):")
        lines.append(f"  - Tipo de día: {menu_hoy.get('tipo_dia', '?')}")
        lines.append(
            f"  - Calorías: {menu_hoy.get('calorias_total', 0)}/{menu_hoy.get('calorias_objetivo', 0)} kcal"
        )
        if menu_hoy.get("costo_total_estimado"):
            lines.append(f"  - Costo estimado: ${menu_hoy['costo_total_estimado']:.0f} MXN")
        for tipo in ("desayuno", "almuerzo", "cena", "snacks"):
            items = menu_hoy.get(tipo) or []
            if items:
                nombres = [it.get("nombre", "?") for it in items]
                lines.append(f"  - {tipo.capitalize()}: {', '.join(nombres)}")
        lines.append(f"  - Consumido: {'sí' if menu_hoy.get('consumido') else 'no'}")
    else:
        lines.append("Menú de hoy: aún no se ha generado uno.")

    eventos = ctx.get("proximos_eventos") or []
    if eventos:
        ev_text = []
        for e in eventos[:4]:
            ev_text.append(f"{e.get('tipo', '?')} {e.get('fecha', '?')}")
        lines.append(f"Próximos eventos: {'; '.join(ev_text)}")
    if ctx.get("tiene_examen_hoy"):
        lines.append("⚠️ TIENE EXAMEN HOY")
    elif ctx.get("tiene_examen_pronto"):
        lines.append("⚠️ Tiene examen en los próximos días")

    semana = ctx.get("semana") or {}
    if semana.get("menus_generados", 0) > 0:
        lines.append(
            f"Semana: {semana.get('comidas_consumidas', 0)}/{semana.get('comidas_totales', 0)} "
            f"comidas consumidas, costo total ${semana.get('costo_total', 0):.0f} MXN"
        )

    # Catálogo resumido de alimentos: solo si la pregunta probablemente
    # requiere sugerencias específicas. Para no inflar tokens, mandamos
    # 25 alimentos representativos (top con etiquetas útiles).
    alimentos_brief = _catalogo_resumido(db, max_items=25)
    if alimentos_brief:
        lines.append("")
        lines.append("Catálogo (extracto, usa estos IDs si recomiendas alimentos):")
        lines.append(alimentos_brief)

    return "\n".join(lines)


def _catalogo_resumido(db: Session, max_items: int = 25) -> str:
    """
    Devuelve un resumen compacto de alimentos del catálogo con sus tags.
    Prioriza alimentos con tags útiles (examen, alta proteína, ligero) para
    que Gemini tenga material para preguntas comunes sin gastar mucho contexto.
    """
    try:
        alimentos = (
            db.query(models.Alimento)
            .order_by(
                # Prioriza alimentos con tags útiles
                models.Alimento.bueno_examen.desc(),
                models.Alimento.alta_proteina.desc(),
                models.Alimento.alto_rendimiento.desc(),
            )
            .limit(max_items)
            .all()
        )
    except Exception:
        logger.exception("Error consultando catálogo de alimentos")
        return ""

    lines = []
    for a in alimentos:
        tags = []
        if a.bueno_examen:     tags.append("examen")
        if a.alta_proteina:    tags.append("proteina")
        if a.alto_rendimiento: tags.append("energia")
        if a.ligero:           tags.append("ligero")
        tags_str = " ".join(tags) if tags else ""
        costo = a.costo_estimado or 0
        lines.append(
            f"  id={a.id_alimento} [{a.tipo_comida}] {a.nombre} "
            f"({a.calorias}kcal P{a.proteinas:.0f}g ${costo:.0f}) {tags_str}".rstrip()
        )
    return "\n".join(lines)


def _build_alimentos_card(db: Session, ids: list) -> Optional[dict]:
    """Construye un context_card con los alimentos que Gemini sugirió por ID."""
    # Filtra a ints válidos y deduplica preservando orden
    seen = set()
    clean_ids = []
    for i in ids:
        if isinstance(i, int) and i not in seen:
            seen.add(i)
            clean_ids.append(i)
    if not clean_ids:
        return None

    alimentos = (
        db.query(models.Alimento)
        .filter(models.Alimento.id_alimento.in_(clean_ids))
        .all()
    )
    if not alimentos:
        return None

    # Preserva el orden con el que Gemini los sugirió
    by_id = {a.id_alimento: a for a in alimentos}
    ordered = [by_id[i] for i in clean_ids if i in by_id]

    return {
        "type": "alimentos_sugeridos",
        "title": "Alimentos sugeridos",
        "items": [
            {
                "id_alimento":    a.id_alimento,
                "nombre":         a.nombre,
                "porcion":        a.porcion,
                "calorias":       a.calorias,
                "proteinas":      a.proteinas,
                "carbohidratos":  a.carbohidratos,
                "grasas":         a.grasas,
                "costo_estimado": a.costo_estimado,
                "tipo_comida":    a.tipo_comida,
            }
            for a in ordered[:5]
        ],
    }


def _menu_card_from_ctx(menu_hoy: dict) -> dict:
    """Estructura del menú de hoy para mostrar como tarjeta en el chat."""
    return {
        "type": "menu_hoy",
        "tipo_dia": menu_hoy.get("tipo_dia"),
        "calorias_total": menu_hoy.get("calorias_total"),
        "calorias_objetivo": menu_hoy.get("calorias_objetivo"),
        "costo_total_estimado": menu_hoy.get("costo_total_estimado"),
        "dentro_presupuesto": menu_hoy.get("dentro_presupuesto"),
        "consumido": menu_hoy.get("consumido"),
    }
