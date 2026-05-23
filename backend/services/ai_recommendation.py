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
        Lista de Alimento elegidos por Gemini (subconjunto de candidatos),
        o None si Gemini no está disponible / falló / devolvió algo inválido.
    """
    client = get_gemini_client()
    if not client.available or not candidatos:
        return None

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
  "razonamiento": "<1-2 frases en español explicando la elección>"
}}"""

    result = client.generate_json(
        prompt=user_prompt,
        system=system_prompt,
        # Temperatura más alta en regeneración para más variedad real
        temperature=0.7 if fresh else 0.4,
        max_tokens=512,
    )

    if not result or "ids_alimentos" not in result:
        return None

    ids_elegidos = result.get("ids_alimentos", [])
    if not isinstance(ids_elegidos, list) or not ids_elegidos:
        return None

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
        return None

    # Logueamos el razonamiento para poder auditar elecciones en producción.
    razonamiento = result.get("razonamiento", "")
    logger.info(
        "Gemini %s%s: eligió %s | razón: %s",
        tipo_comida, " (fresh)" if fresh else "",
        [a.id_alimento for a in elegidos], razonamiento[:200],
    )

    return elegidos


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
