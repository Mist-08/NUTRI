"""
Capa de IA encima del motor de recomendación.

Usa Gemini para:
1) `pick_meal_with_gemini`: elegir la mejor combinación de alimentos para una
   comida específica, sobre el conjunto de candidatos que ya filtró/rankeó el
   motor de reglas. Si Gemini falla, el caller usa su selección rule-based.

2) `generate_personalized_message`: redactar un mensaje motivador y
   personalizado para acompañar el menú del día. Si Gemini falla, el caller
   usa el mensaje estático del motor.

Política: Gemini NUNCA inventa alimentos; solo elige IDs del catálogo real.
Esto evita que la IA alucine calorías, precios o macros.
"""

import logging
import random
from typing import Optional

import models
from services.gemini_client import get_gemini_client

logger = logging.getLogger(__name__)


# ══════════════════════════════════════════════════════════════════════
#  SELECCIÓN DE ALIMENTOS POR COMIDA
# ══════════════════════════════════════════════════════════════════════

def pick_meal_with_gemini(
    candidatos: list[models.Alimento],
    tipo_comida: str,
    cal_meta: int,
    contexto: dict,
    perfil: models.PerfilNutricional,
    disliked_names: Optional[set] = None,
    max_items: int = 3,
    fresh: bool = False,  # True cuando es regeneración → más variedad
) -> Optional[list[models.Alimento]]:
    """
    Pide a Gemini que escoja la mejor combinación de candidatos para una
    comida (Desayuno/Almuerzo/Cena/Snack).

    Args:
        candidatos:     lista de alimentos del catálogo, ya filtrada por
                        restricciones y ranqueada por el motor de reglas.
        tipo_comida:    "Desayuno" | "Almuerzo" | "Cena" | "Snack"
        cal_meta:       calorías objetivo para esta comida
        contexto:       dict con tipo_dia, exámenes, etc.
        perfil:         PerfilNutricional del usuario
        disliked_names: nombres de alimentos rechazados antes por el usuario
        max_items:      máximo de alimentos a devolver
        fresh:          si True, se mezcla el orden de candidatos para que la
                        regeneración produzca variedad real, no siempre lo mismo

    Returns:
        Tupla (lista de Alimento elegidos, razonamiento str). Si Gemini no
        está disponible / falló / devolvió algo inválido, devuelve (None, "").
    """
    client = get_gemini_client()
    if not client.available or not candidatos:
        return None, ""

    # Limita el catálogo enviado al prompt para no inflar tokens.
    # Tomamos top-10 por score rule-based. En regeneración, mezclamos un poco
    # el orden de los siguientes para forzar variedad sin perder calidad.
    top_n = min(12, len(candidatos))
    if fresh and len(candidatos) > 6:
        # Conserva el top-3 (los mejores) y baraja los siguientes 9 para
        # exponerle a Gemini un set distinto cada regeneración.
        top_candidatos = list(candidatos[:3])
        resto = list(candidatos[3:top_n])
        random.shuffle(resto)
        top_candidatos.extend(resto)
    else:
        top_candidatos = candidatos[:top_n]

    catalogo_lines = []
    for a in top_candidatos:
        etiquetas = []
        if a.bueno_examen:     etiquetas.append("examen")
        if a.alta_proteina:    etiquetas.append("altaProteina")
        if a.alto_rendimiento: etiquetas.append("altoRendimiento")
        if a.ligero:           etiquetas.append("ligero")
        tags = " ".join(etiquetas) if etiquetas else "-"

        catalogo_lines.append(
            f"id={a.id_alimento} | {a.nombre} | "
            f"{a.calorias}kcal P{a.proteinas:.0f}g C{a.carbohidratos:.0f}g G{a.grasas:.0f}g | "
            f"${(a.costo_estimado or 0):.0f}MXN | {tags}"
        )
    catalogo = "\n".join(catalogo_lines)

    disliked_section = ""
    if disliked_names:
        sample = list(disliked_names)[:15]   # límite por si son muchos
        disliked_section = (
            f"\nALIMENTOS QUE EL USUARIO RECHAZÓ ANTES (NO los incluyas aunque "
            f"aparezcan en candidatos):\n{', '.join(sample)}\n"
        )

    system_prompt = (
        "Eres un nutricionista virtual de NutriCampus AI especializado en "
        "estudiantes universitarios mexicanos. Tu objetivo es combinar "
        "alimentos de un catálogo dado para armar comidas balanceadas, "
        "respetando salud, presupuesto y carga académica. "
        "Respondes SIEMPRE en JSON estricto y solo eliges IDs presentes "
        "en el catálogo entregado."
    )

    user_prompt = f"""Selecciona la MEJOR combinación de hasta {max_items} alimentos para {tipo_comida.upper()}.

CONTEXTO DEL USUARIO:
- Objetivo: {perfil.objetivo or 'Mantener'}
- Nivel de actividad: {perfil.nivel_actividad or 'Moderado'}
- Tipo de día: {contexto.get('tipo_dia', 'normal')}
- Dieta: {perfil.dieta or 'Sin restricciones'}
- Nivel presupuesto: {perfil.nivel_presupuesto or 'medio'}
- Tipo menú preferido: {perfil.tipo_menu_preferido or 'balanceado'}
- Calorías objetivo para esta comida: {cal_meta} kcal (margen ±80)
{disliked_section}
CANDIDATOS (ya filtrados por restricciones y alergias):
{catalogo}

REGLAS DE SELECCIÓN OBLIGATORIAS:
1. NUNCA repitas el mismo ID en ids_alimentos. Cada ID debe ser único.
2. Combina alimentos DIFERENTES (no 2 versiones del mismo platillo).
3. Acércate a {cal_meta} kcal; no excedas {cal_meta + 80}.
4. Mezcla realista: idealmente proteína + carbohidrato + verdura/fruta.
5. Día "examen": prioriza alimentos con tag "examen" y "ligero".
6. Día "alta_carga": prioriza "altoRendimiento" o "altaProteina".
7. Objetivo "Bajar peso": prioriza "ligero" y menos calorías.
8. Objetivo "Subir masa" o "Mejorar rendimiento": prioriza "altaProteina".
9. Si presupuesto=bajo, elige los más baratos sin sacrificar nutrición.

RESPONDE SOLO CON ESTE JSON, sin markdown, sin texto adicional:
{{
  "ids_alimentos": [<lista de IDs ÚNICOS del catálogo>],
  "razonamiento": "<MÁXIMO 25 palabras en español; por qué elegiste estos alimentos>"
}}"""

    result = client.generate_json(
        prompt=user_prompt,
        system=system_prompt,
        # Temperatura más alta en regeneración para más variedad real
        temperature=0.7 if fresh else 0.4,
        max_tokens=1024,   # holgado: evita cortar el JSON si el razonamiento se alarga
    )

    if not result or "ids_alimentos" not in result:
        return None, ""

    ids_elegidos = result.get("ids_alimentos", [])
    if not isinstance(ids_elegidos, list) or not ids_elegidos:
        return None, ""

    # Mapea IDs a objetos reales. DEDUPLICA preservando el orden de Gemini
    # (por si el modelo ignora la regla anti-duplicados).
    by_id = {a.id_alimento: a for a in candidatos}
    elegidos: list[models.Alimento] = []
    seen: set[int] = set()
    for i in ids_elegidos:
        if not isinstance(i, int):
            continue
        if i in seen:
            logger.info("Gemini devolvió ID duplicado %d en %s; descartado", i, tipo_comida)
            continue
        if i not in by_id:
            logger.warning("Gemini devolvió ID inválido %d en %s; descartado", i, tipo_comida)
            continue
        elegidos.append(by_id[i])
        seen.add(i)
        if len(elegidos) >= max_items:
            break

    if not elegidos:
        logger.warning(
            "Gemini devolvió 0 IDs válidos para %s: %s",
            tipo_comida, ids_elegidos,
        )
        return None, ""

    # Logueamos el razonamiento para poder auditar elecciones en producción.
    razonamiento = result.get("razonamiento", "")
    if not isinstance(razonamiento, str):
        razonamiento = ""
    razonamiento = razonamiento.strip()
    logger.info(
        "Gemini %s%s: eligió %s | razón: %s",
        tipo_comida, " (fresh)" if fresh else "",
        [a.id_alimento for a in elegidos], razonamiento[:200],
    )

    return elegidos, razonamiento


# ══════════════════════════════════════════════════════════════════════
#  MENÚ COMPLETO EN UNA SOLA LLAMADA
# ══════════════════════════════════════════════════════════════════════

# Claves JSON (sin acentos) ↔ tipo_comida del catálogo
_KEY_POR_TIPO = {
    "Desayuno": "desayuno",
    "Almuerzo": "almuerzo",
    "Cena":     "cena",
    "Snack":    "snack",
}


def _formatear_candidatos(candidatos: list[models.Alimento], fresh: bool, top_n: int = 8) -> list[models.Alimento]:
    """Recorta a top_n candidatos; si fresh, baraja para dar variedad."""
    n = min(top_n, len(candidatos))
    if fresh and len(candidatos) > 4:
        cabeza = list(candidatos[:2])
        resto = list(candidatos[2:n])
        random.shuffle(resto)
        return cabeza + resto
    return candidatos[:n]


def _linea_catalogo(a: models.Alimento) -> str:
    etiquetas = []
    if a.bueno_examen:     etiquetas.append("examen")
    if a.alta_proteina:    etiquetas.append("altaProteina")
    if a.alto_rendimiento: etiquetas.append("altoRendimiento")
    if a.ligero:           etiquetas.append("ligero")
    tags = " ".join(etiquetas) if etiquetas else "-"
    return (
        f"id={a.id_alimento} | {a.nombre} | "
        f"{a.calorias}kcal P{a.proteinas:.0f}g C{a.carbohidratos:.0f}g G{a.grasas:.0f}g | "
        f"${(a.costo_estimado or 0):.0f}MXN | {tags}"
    )


def pick_full_menu_with_gemini(
    candidatos_por_tipo: dict,      # {"Desayuno": [Alimento,...], ...}
    cal_meta_por_tipo: dict,        # {"Desayuno": 500, ...}
    contexto: dict,
    perfil: models.PerfilNutricional,
    disliked_names: Optional[set] = None,
    max_items: int = 1,
    fresh: bool = False,
) -> Optional[dict]:
    """
    Elige las 4 comidas del menú (Desayuno/Almuerzo/Cena/Snack) y redacta el
    mensaje del día en UNA SOLA llamada a Gemini.

    Returns:
        dict {tipo: [Alimento,...], "_mensaje": str|None}, solo con las comidas
        que Gemini resolvió correctamente. Devuelve None si Gemini no está
        disponible o la respuesta fue inválida (el caller usa fallback por comida).
    """
    client = get_gemini_client()
    if not client.available:
        return None

    tipos_con_candidatos = [t for t in ("Desayuno", "Almuerzo", "Cena", "Snack")
                            if candidatos_por_tipo.get(t)]
    if not tipos_con_candidatos:
        return None

    # Mapa global id→Alimento (para resolver los IDs que devuelva Gemini)
    by_id: dict[int, models.Alimento] = {}
    secciones = []
    for tipo in tipos_con_candidatos:
        seleccion = _formatear_candidatos(candidatos_por_tipo[tipo], fresh)
        for a in seleccion:
            by_id[a.id_alimento] = a
        lineas = "\n".join(_linea_catalogo(a) for a in seleccion)
        cal_meta = cal_meta_por_tipo.get(tipo, 0)
        secciones.append(
            f"=== {tipo.upper()} (objetivo ~{cal_meta} kcal) ===\n{lineas}"
        )
    catalogo = "\n\n".join(secciones)

    disliked_section = ""
    if disliked_names:
        sample = list(disliked_names)[:15]
        disliked_section = (
            f"\nALIMENTOS QUE EL USUARIO RECHAZÓ ANTES (NO los incluyas):\n"
            f"{', '.join(sample)}\n"
        )

    # Claves JSON esperadas (solo las comidas con candidatos)
    keys = [_KEY_POR_TIPO[t] for t in tipos_con_candidatos]
    ejemplo_keys = ",\n  ".join(f'"{k}": [<IDs>]' for k in keys)
    razones_keys = ", ".join(f'"{k}": "<motivo breve>"' for k in keys)

    system_prompt = (
        "Eres un nutricionista virtual de NutriCampus AI para estudiantes "
        "universitarios mexicanos. Armas un menú diario balanceado eligiendo "
        "alimentos de un catálogo dado, respetando salud, presupuesto y carga "
        "académica. Respondes SIEMPRE en JSON estricto y solo eliges IDs "
        "presentes en el catálogo."
    )

    user_prompt = f"""Arma el MENÚ COMPLETO del día eligiendo EXACTAMENTE {max_items} alimento(s) por comida.

CONTEXTO DEL USUARIO:
- Objetivo: {perfil.objetivo or 'Mantener'}
- Nivel de actividad: {perfil.nivel_actividad or 'Moderado'}
- Tipo de día: {contexto.get('tipo_dia', 'normal')}
- Dieta: {perfil.dieta or 'Sin restricciones'}
- Nivel presupuesto: {perfil.nivel_presupuesto or 'medio'}
- Tipo menú preferido: {perfil.tipo_menu_preferido or 'balanceado'}
{disliked_section}
CANDIDATOS POR COMIDA (ya filtrados por restricciones y alergias):
{catalogo}

REGLAS OBLIGATORIAS:
1. Elige EXACTAMENTE {max_items} alimento(s) por comida, solo IDs del catálogo de ESA comida.
2. No repitas el mismo alimento en comidas distintas.
3. Acércate al objetivo de calorías de cada comida.
4. Día "examen": prioriza tags "examen" y "ligero". Día "alta_carga": "altoRendimiento"/"altaProteina".
5. Objetivo "Bajar peso": prioriza "ligero". "Subir masa"/"Mejorar rendimiento": prioriza "altaProteina".
6. Si presupuesto=bajo, elige los más baratos sin sacrificar nutrición.
7. El "mensaje": máx 3 frases, español de México tuteando, cálido y directo, sin emojis, sin saludos ni despedidas; conecta el menú con el tipo de día.
8. En "razones": por cada comida, MÁXIMO 20 palabras explicando por qué elegiste ese alimento.

RESPONDE SOLO CON ESTE JSON, sin markdown ni texto adicional:
{{
  {ejemplo_keys},
  "razones": {{ {razones_keys} }},
  "mensaje": "<mensaje del día>"
}}"""

    result = client.generate_json(
        prompt=user_prompt,
        system=system_prompt,
        temperature=0.7 if fresh else 0.4,
        max_tokens=3072,   # holgado: 4 comidas + 4 razones + mensaje sin cortar el JSON
    )
    if not result or not isinstance(result, dict):
        return None

    razones_in = result.get("razones") if isinstance(result.get("razones"), dict) else {}

    salida: dict = {}
    razones_out: dict = {}
    for tipo in tipos_con_candidatos:
        key = _KEY_POR_TIPO[tipo]
        ids = result.get(key, [])
        if not isinstance(ids, list):
            continue
        elegidos: list[models.Alimento] = []
        seen: set[int] = set()
        for i in ids:
            if not isinstance(i, int) or i in seen or i not in by_id:
                continue
            # Respeta el tipo: el id debe pertenecer a ESTA comida
            if by_id[i].tipo_comida != tipo:
                continue
            elegidos.append(by_id[i])
            seen.add(i)
            if len(elegidos) >= max_items:
                break
        if elegidos:
            salida[tipo] = elegidos
            r = razones_in.get(key)
            if isinstance(r, str) and r.strip():
                razones_out[tipo] = r.strip()

    if not salida:
        logger.warning("Gemini menú completo: 0 comidas válidas | result keys=%s", list(result.keys()))
        return None

    if razones_out:
        salida["_razones"] = razones_out

    mensaje = result.get("mensaje")
    if isinstance(mensaje, str):
        mensaje = mensaje.strip().strip('"\'').strip()
        if 20 <= len(mensaje) <= 800:
            salida["_mensaje"] = mensaje

    logger.info(
        "Gemini menú completo%s: %s | mensaje=%s",
        " (fresh)" if fresh else "",
        {t: [a.id_alimento for a in salida[t]] for t in salida if not t.startswith("_")},
        "sí" if salida.get("_mensaje") else "no",
    )
    return salida


# ══════════════════════════════════════════════════════════════════════
#  MENSAJE PERSONALIZADO
# ══════════════════════════════════════════════════════════════════════

def generate_personalized_message(
    perfil: models.PerfilNutricional,
    contexto: dict,
    menu_items: dict,   # {"Desayuno": [Alimento, ...], "Almuerzo": [...], ...}
    costo_total: float,
    dentro_presupuesto: Optional[bool],
) -> Optional[str]:
    """
    Pide a Gemini un mensaje cálido y personalizado para el menú del día.
    Devuelve None si Gemini no está disponible o el texto resultante es sospechoso
    (muy corto, muy largo, etc.) — el caller usa el mensaje estático del motor.
    """
    client = get_gemini_client()
    if not client.available:
        return None

    # Resumen compacto del menú para el prompt
    items_text = []
    for tipo, items in menu_items.items():
        if items:
            nombres = ", ".join(a.nombre for a in items)
            items_text.append(f"  {tipo}: {nombres}")
    menu_resumen = "\n".join(items_text) if items_text else "(sin menú)"

    ppto_estado = (
        "dentro del presupuesto" if dentro_presupuesto is True
        else "sobre el presupuesto" if dentro_presupuesto is False
        else "sin presupuesto definido"
    )

    system_prompt = (
        "Eres un nutricionista cercano y motivador. Escribes en español de "
        "México, tuteando al usuario. Tono cálido, directo, sin clichés ni "
        "frases huecas. Máximo 3 frases. Sin emojis. Sin saludos ni despedidas."
    )

    user_prompt = f"""Genera el mensaje del día para acompañar el menú de un estudiante universitario.

PERFIL:
- Objetivo: {perfil.objetivo or 'Mantener'}
- Tipo de día: {contexto.get('tipo_dia', 'normal')}
- Costo del día: ${costo_total:.0f} MXN ({ppto_estado})

MENÚ DE HOY:
{menu_resumen}

REGLAS:
- Máximo 3 frases, mínimo 1
- Conecta el menú con el día: si hay examen, menciona concentración; si es alta_carga, menciona energía sostenida; si es descanso, menciona recuperación
- Si está sobre presupuesto, dilo brevemente sin regañar
- No saludes, no te despidas, ve directo al mensaje
- Sin emojis ni decoración
- Habla del menú, no de ti

Responde solo con el texto del mensaje, sin comillas ni formato."""

    text = client.generate(
        prompt=user_prompt,
        system=system_prompt,
        temperature=0.7,
        max_tokens=256,
    )

    if not text:
        return None

    # Limpia comillas externas que a veces aparecen
    text = text.strip().strip('"\'').strip()

    # Sanity check: longitudes razonables
    if len(text) < 20 or len(text) > 800:
        logger.warning(
            "Mensaje de Gemini con longitud sospechosa (%d chars), usando fallback",
            len(text),
        )
        return None

    return text
