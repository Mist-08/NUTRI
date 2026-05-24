"""
Servicio principal del chatbot de NutriCampus AI — "Asistente NutriCampus".

Genera respuestas personalizadas basadas en el contexto del usuario
y la intención detectada. Soporta multi-intención, extracción de
entidades y fallback semántico por topic scoring. No requiere APIs externas.
"""

import re
import random
import logging
from typing import List, Optional

from services.chatbot_intents import (
    detect_all_intents,
    extract_entities,
    classify_message,
    dominant_topic,
)

logger = logging.getLogger(__name__)

# ── Colecciones de sugerencias ────────────────────────────────────

DEFAULT_SUGGESTIONS = [
    "¿Qué debo comer hoy?",
    "¿Qué puedo comer con poco presupuesto?",
    "Dame snacks para estudiar",
    "¿Cuántas calorías he consumido esta semana?",
    "¿Qué comer el día de mi examen?",
    "¿Cuánto he gastado en comida esta semana?",
]

EXAM_SUGGESTIONS = [
    "¿Qué debo comer antes del examen?",
    "Dame snacks para estudiar",
    "¿Qué alimentos mejoran la concentración?",
]

BUDGET_SUGGESTIONS = [
    "¿Cuál es mi opción más económica hoy?",
    "¿Cuánto he gastado esta semana?",
    "Dame un plan económico para la semana",
]


# ── Punto de entrada ──────────────────────────────────────────────

def process_message(message: str, context: dict) -> dict:
    """
    Procesa un mensaje y devuelve la respuesta del chatbot.

    Usa dos capas de detección:
    1. Regex patterns (intents precisos) — layer 1
    2. Topic scoring semántico — fallback cuando regex da 'desconocido'

    Siempre devuelve un dict válido; nunca lanza excepción al llamador.
    """
    try:
        entities = extract_entities(message)
        intents, scores, topic = classify_message(message)

        logger.info(
            "chatbot msg=%r intents=%s topic=%s entities=%s",
            message[:80],
            intents,
            topic,
            entities,
        )

        enriched = {**context, "_entities": entities, "_scores": scores}

        # ── Multi-intención: prioridades especiales por combinación
        if "menu_examen" in intents and "menu_economico" in intents:
            return _handle_examen_economico(message, enriched, entities)

        if "objetivo_consulta" in intents and "menu_economico" in intents:
            return _handle_objetivo_economico(message, enriched, "objetivo_consulta")

        # Comida específica + barato → handler de comida (ya maneja presupuesto)
        for comida_intent in ("cena_consulta", "desayuno_consulta", "almuerzo_consulta"):
            if comida_intent in intents and "menu_economico" in intents:
                handler = _HANDLERS[comida_intent]
                return handler(message, enriched, comida_intent)

        # explicar_menu tiene prioridad sobre que_comer_hoy cuando ambos presentes
        if "explicar_menu" in intents:
            return _handle_explicar_menu(message, enriched, "explicar_menu")

        # ── Intención primaria por regex
        primary = intents[0] if intents else "desconocido"

        if primary != "desconocido":
            handler = _HANDLERS.get(primary, _handle_desconocido)
            return handler(message, enriched, primary)

        # ── Layer 2: fallback semántico cuando regex no detectó nada
        if topic:
            return _handle_fuzzy(topic, message, enriched)

        return _handle_desconocido(message, enriched, "desconocido")

    except Exception:
        logger.exception("Error fatal en process_message (msg=%r)", message[:80])
        return {
            "reply": (
                "Hubo un problema al procesar tu mensaje. "
                "Por favor, intenta de nuevo en unos segundos."
            ),
            "intent": "error",
            "suggestions": DEFAULT_SUGGESTIONS[:3],
            "related_menu": None,
            "context_card": None,
        }


# ── Fallback semántico (layer 2) ──────────────────────────────────

def _handle_fuzzy(topic: str, message: str, ctx: dict) -> dict:
    """
    Genera una respuesta contextual cuando el topic scoring detectó tema
    pero los regex de intención no tuvieron match exacto.
    """
    entities = ctx.get("_entities") or {}

    if topic == "economia":
        # "No tengo mucho dinero, qué puedo comer" → menú económico
        return _handle_menu_economico(message, ctx, "menu_economico")

    if topic == "examen":
        # "Mañana tengo parcial" → consejos para examen
        return _handle_menu_examen(message, ctx, "menu_examen")

    if topic == "snacks":
        return _handle_snacks_estudio(message, ctx, "snacks_estudio")

    if topic == "calorias":
        return _handle_calorias_consulta(message, ctx, "calorias_consulta")

    if topic == "objetivo":
        # "Estoy en volumen y tengo poco presupuesto"
        scores = ctx.get("_scores") or {}
        if scores.get("economia", 0) > 0.4:
            return _handle_objetivo_economico(message, ctx, "objetivo_consulta")
        return _handle_objetivo_consulta(message, ctx, "objetivo_consulta")

    if topic == "nutricion":
        return _handle_consejo_nutricion(message, ctx, "consejo_nutricion")

    if topic == "comida_general":
        # "Qué como hoy" / "algo para cenar" / "qué me recomiendas"
        msg_lower = message.lower()
        if re.search(r"cen[aá]|cenar", msg_lower):
            return _handle_cena_consulta(message, ctx, "cena_consulta")
        if re.search(r"desayun", msg_lower):
            return _handle_desayuno_consulta(message, ctx, "desayuno_consulta")
        if re.search(r"almuerz|almorzar", msg_lower):
            return _handle_almuerzo_consulta(message, ctx, "almuerzo_consulta")
        return _handle_que_comer_hoy(message, ctx, "que_comer_hoy")

    return _handle_desconocido(message, ctx, "desconocido")


# ── Handler especial: examen + presupuesto combinados ─────────────

def _handle_examen_economico(message: str, ctx: dict, entities: dict) -> dict:
    """Responde a mensajes tipo 'Tengo examen mañana y solo tengo 80 pesos'."""
    if not ctx.get("tiene_perfil"):
        return _sin_perfil("menu_examen+menu_economico")

    monto = entities.get("monto")
    tiempo = entities.get("tiempo", "manana")

    intro = ""
    if tiempo == "hoy":
        intro = "¡Hoy es el día del examen! "
    elif tiempo == "manana":
        intro = "Tienes examen mañana, ¡vamos a prepararte bien! "
    elif tiempo == "pasado_manana":
        intro = "Tienes examen pasado mañana. Todavía hay tiempo para prepararte. "

    if monto:
        intro += f"Y tienes **${monto} MXN** para comer — con eso podemos armar un plan.\n\n"
    else:
        intro += "Con presupuesto ajustado también podemos lograrlo.\n\n"

    reply = intro + (
        "**Plan económico para rendir en el examen:**\n\n"
        "🌅 **Desayuno (prioridad máxima):**\n"
        "• Avena con plátano y miel (~$25) — energía estable y sostenida\n"
        "• O huevos revueltos con tortilla (~$30) — proteína para concentración\n\n"
        "☀️ **Almuerzo (ligero para no sentirte pesado):**\n"
        "• Arroz con frijoles y nopal (~$35) — carbohidratos sin pesadez\n"
        "• O sopa de verduras con pollo (~$45) — fácil de digerir\n\n"
        "🍎 **Snacks de estudio:**\n"
        "• Fruta de temporada (~$15) — vitaminas y azúcar natural\n"
        "• Agua de jamaica (~$10) — hidratación sin cafeína extra\n\n"
        "💧 **¡Hidratación es clave!** Mínimo 2 litros hoy.\n"
    )

    if monto:
        total_min = 25 + 35 + 15 + 10
        if monto >= total_min:
            sobra = monto - total_min
            reply += (
                f"\n✅ Con **${monto} MXN** te alcanza para el plan completo "
                f"y te sobran ~${sobra} MXN para lo que necesites."
            )
        else:
            reply += (
                f"\n⚠️ Con **${monto} MXN** es bastante justo. "
                "Prioriza el desayuno y evita saltarte comidas — come algo aunque sea sencillo."
            )

    return {
        "reply": reply.strip(),
        "intent": "menu_examen+menu_economico",
        "suggestions": EXAM_SUGGESTIONS[:2] + BUDGET_SUGGESTIONS[:1],
        "related_menu": _menu_card(ctx.get("menu_hoy")),
        "context_card": _exam_card(ctx),
    }


# ── Handlers individuales ─────────────────────────────────────────

def _handle_identidad(message: str, ctx: dict, intent: str) -> dict:
    return {
        "reply": (
            "Soy el **Asistente NutriCampus**, tu guía de alimentación personalizada. "
            "Puedo ayudarte con:\n\n"
            "• Recomendaciones de menú según tu agenda académica\n"
            "• Planificación de comidas dentro de tu presupuesto\n"
            "• Alimentación para días de examen o entregas\n"
            "• Snacks saludables para estudiar\n"
            "• Seguimiento de calorías y gastos de comida\n\n"
            "Todo sin depender de APIs externas — mis respuestas son locales e instantáneas. "
            "¿En qué te ayudo hoy?"
        ),
        "intent": intent,
        "suggestions": DEFAULT_SUGGESTIONS[:4],
        "related_menu": None,
        "context_card": None,
    }


def _handle_saludo(message: str, ctx: dict, intent: str) -> dict:
    dia = ctx.get("dia_semana", "")
    replies = [
        "¡Hola! Soy el Asistente NutriCampus. Estoy aquí para ayudarte a comer bien "
        "y aprovechar tu presupuesto. ¿En qué te puedo ayudar hoy?",
        f"¡Buenas! ¿Listo/a para comer bien este {dia}? Cuéntame qué necesitas.",
        "¡Hola! Puedo ayudarte con tu menú del día, presupuesto alimentario, "
        "snacks para estudiar y más. ¿Qué necesitas?",
    ]
    return {
        "reply": random.choice(replies),
        "intent": intent,
        "suggestions": DEFAULT_SUGGESTIONS[:4],
        "related_menu": None,
        "context_card": None,
    }


def _handle_que_comer_hoy(message: str, ctx: dict, intent: str) -> dict:
    if not ctx.get("tiene_perfil"):
        return _sin_perfil(intent)

    menu = ctx.get("menu_hoy")
    if menu:
        desayuno = [a["nombre"] for a in (menu.get("desayuno") or [])]
        almuerzo = [a["nombre"] for a in (menu.get("almuerzo") or [])]
        cena = [a["nombre"] for a in (menu.get("cena") or [])]

        dia = ctx.get("dia_semana", "hoy")
        reply = (
            f"Tu menú de hoy ({dia}) ya está listo:\n\n"
            f"🌅 **Desayuno:** {', '.join(desayuno) or 'Sin sugerencia'}\n"
            f"☀️ **Almuerzo:** {', '.join(almuerzo) or 'Sin sugerencia'}\n"
            f"🌙 **Cena:** {', '.join(cena) or 'Sin sugerencia'}\n\n"
        )
        costo = menu.get("costo_total_estimado")
        if costo:
            reply += f"💰 Costo estimado del día: **${costo:.0f} MXN**\n"
        if menu.get("dentro_presupuesto") is True:
            reply += "✅ Está dentro de tu presupuesto.\n"
        elif menu.get("dentro_presupuesto") is False:
            reply += "⚠️ Este menú supera tu presupuesto diario.\n"
        if menu.get("tipo_dia") == "examen":
            reply += "\n🧪 Es día de examen: tu menú favorece la concentración. ¡Ánimo!"

        return {
            "reply": reply.strip(),
            "intent": intent,
            "suggestions": ["¿Por qué este menú?", "Dame snacks para estudiar", "¿Cuántas calorías tiene?"],
            "related_menu": _menu_card(menu),
            "context_card": None,
        }
    else:
        return {
            "reply": (
                "Aún no tienes un menú generado para hoy. "
                "Ve a la pantalla de **Recomendación** para generarlo automáticamente "
                "según tu perfil y agenda."
            ),
            "intent": intent,
            "suggestions": ["¿Qué comer si tengo examen?", "Dame snacks para estudiar"],
            "related_menu": None,
            "context_card": None,
        }


def _handle_cena_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre qué cenar."""
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()
    entities = ctx.get("_entities") or {}
    es_barata = nivel_ppto == "bajo" or entities.get("monto", 999) < 100

    reply = "🌙 **Ideas para la cena:**\n\n"

    if es_barata:
        reply += (
            "**Opciones económicas (< $45 MXN):**\n"
            "• Frijoles de olla con arroz y tortilla (~$30) — completo y nutritivo\n"
            "• Sopa de verduras ligera con pan (~$25) — fácil de digerir de noche\n"
            "• Tacos de frijoles y nopales (~$35) — fibra y proteína vegetal\n"
            "• Huevos revueltos con tortilla (~$30) — rápido y económico\n\n"
        )
    elif objetivo == "Bajar peso":
        reply += (
            "**Opciones ligeras para bajar peso:**\n"
            "• Ensalada verde con pollo a la plancha (~$55)\n"
            "• Sopa de verduras sin grasa (~$35)\n"
            "• Pescado al vapor con verduras (~$65)\n\n"
        )
    elif objetivo == "Subir masa":
        reply += (
            "**Opciones con proteína para subir masa:**\n"
            "• Pechuga de pollo con arroz y brócoli (~$65)\n"
            "• Atún con tortilla y aguacate (~$55)\n"
            "• Huevos con frijoles y quesillo (~$50)\n\n"
        )
    else:
        reply += (
            "**Opciones balanceadas:**\n"
            "• Caldo de pollo con verduras (~$50) — ligero y reconfortante\n"
            "• Tacos de verduras con guacamole (~$45) — colorido y saludable\n"
            "• Sopa de lentejas con tortilla (~$40) — proteína vegetal completa\n\n"
        )

    reply += "💡 **Consejo:** La cena debe ser ligera — es la última comida antes de dormir."

    menu = ctx.get("menu_hoy")
    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "Dame snacks para estudiar", "¿Qué puedo cenar barato?"],
        "related_menu": _menu_card(menu) if menu else None,
        "context_card": None,
    }


def _handle_desayuno_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre qué desayunar."""
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()
    entities = ctx.get("_entities") or {}
    es_barato = nivel_ppto == "bajo" or entities.get("monto", 999) < 100

    reply = "🌅 **Ideas para el desayuno:**\n\n"

    if es_barato:
        reply += (
            "**Opciones económicas (< $35 MXN):**\n"
            "• Avena con plátano y miel (~$25) — energía duradera y barata\n"
            "• Huevos revueltos con tortilla y frijoles (~$30) — proteína completa\n"
            "• Pan integral con frijoles (~$20) — sencillo y nutritivo\n"
            "• Fruta de temporada con granola (~$30) — vitaminas y fibra\n\n"
        )
    elif objetivo == "Subir masa":
        reply += (
            "**Desayunos altos en proteína:**\n"
            "• Omelette de 3 huevos con queso y verduras (~$45)\n"
            "• Avena con proteína en polvo y plátano (~$50)\n"
            "• Yogur griego con granola y frutos secos (~$55)\n\n"
        )
    elif objetivo == "Bajar peso":
        reply += (
            "**Desayunos ligeros y saciantes:**\n"
            "• Smoothie verde (espinaca, manzana, limón) (~$35)\n"
            "• Huevos pochados con aguacate (~$50)\n"
            "• Avena con fruta sin azúcar añadida (~$30)\n\n"
        )
    else:
        reply += (
            "**Desayunos balanceados:**\n"
            "• Avena con fruta y miel (~$30) — el clásico universitario\n"
            "• Huevos con frijoles y tortilla (~$35) — completo y versátil\n"
            "• Smoothie con avena y plátano (~$35) — rápido para días ocupados\n\n"
        )

    examen_hoy = ctx.get("tiene_examen_hoy") or ctx.get("tiene_examen_pronto")
    if examen_hoy:
        reply += "🧠 **Tip examen:** Desayuna 1-2 horas antes — sin estómago vacío ni demasiado lleno."
    else:
        reply += "💡 **Recuerda:** El desayuno es el combustible de tu mañana académica. ¡No lo saltes!"

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué puedo comer con poco presupuesto?", "Dame snacks para estudiar"],
        "related_menu": _menu_card(ctx.get("menu_hoy")) if ctx.get("menu_hoy") else None,
        "context_card": None,
    }


def _handle_almuerzo_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre qué almorzar."""
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()
    entities = ctx.get("_entities") or {}
    es_barato = nivel_ppto == "bajo" or entities.get("monto", 999) < 100

    reply = "☀️ **Ideas para el almuerzo:**\n\n"

    if es_barato:
        reply += (
            "**Opciones económicas (< $55 MXN):**\n"
            "• Arroz con frijoles negros y ensalada (~$35) — completo y nutritivo\n"
            "• Lentejas guisadas con tortilla (~$40) — hierro y proteína vegetal\n"
            "• Tacos de papa con verduras (~$35) — sabroso y accesible\n"
            "• Sopa de verduras con pollo desmenuzado (~$45) — reconfortante\n\n"
        )
    elif objetivo == "Subir masa":
        reply += (
            "**Almuerzos altos en proteína:**\n"
            "• Pechuga de pollo con arroz y ensalada (~$65)\n"
            "• Atún al natural con pasta integral (~$60)\n"
            "• Bowl de quinoa con huevo duro y aguacate (~$70)\n\n"
        )
    else:
        reply += (
            "**Almuerzos balanceados:**\n"
            "• Bowl de pollo con arroz y guacamole (~$65)\n"
            "• Sopa de fideos con pollo y verduras (~$50)\n"
            "• Tacos de frijoles negros con nopales (~$40)\n"
            "• Ensalada con tuna y pan integral (~$55)\n\n"
        )

    examen = ctx.get("tiene_examen_hoy") or ctx.get("tiene_examen_pronto")
    if examen:
        reply += "🧪 **Día de examen:** Elige opciones ligeras — nada muy pesado que te dé sueño."
    else:
        reply += "💡 **Tip:** El almuerzo es tu recarga de energía para la tarde. Inclúyelo siempre."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué puedo comer con poco presupuesto?", "¿Qué debo comer hoy?"],
        "related_menu": _menu_card(ctx.get("menu_hoy")) if ctx.get("menu_hoy") else None,
        "context_card": None,
    }


def _handle_menu_examen(message: str, ctx: dict, intent: str) -> dict:
    if not ctx.get("tiene_perfil"):
        return _sin_perfil(intent)

    tiene_examen_hoy = ctx.get("tiene_examen_hoy", False)
    tiene_examen_pronto = ctx.get("tiene_examen_pronto", False)

    body = (
        "Para días de examen, lo ideal es:\n\n"
        "🌅 **Desayuno:** Ligero y de energía estable: avena con plátano, smoothie verde, "
        "yogur con fruta o tostadas con aguacate.\n\n"
        "☀️ **Almuerzo:** Fácil de digerir: sopa de verduras con pollo, ensalada con proteína "
        "o bowl de quinoa. Evita comidas muy pesadas.\n\n"
        "🌙 **Cena (noche anterior):** Carbohidratos complejos + proteína: caldo de pollo, "
        "frijoles con arroz u omelet de espinacas.\n\n"
        "🧠 **Snacks clave:** Fruta, nueces o yogur griego mientras estudias.\n"
        "💧 ¡Hidratación fundamental: mínimo 2 litros de agua!"
    )

    if tiene_examen_hoy:
        prefix = "¡Tienes examen **hoy**! "
    elif tiene_examen_pronto:
        proximos = ctx.get("proximos_eventos") or []
        examenes = [e for e in proximos if e.get("tipo") == "Examen"]
        if examenes:
            e = examenes[0]
            prefix = f"Tienes un examen el **{e['fecha']}** ({e.get('descripcion', 'Examen')}). "
        else:
            prefix = "Tienes un examen próximamente. "
    else:
        prefix = ""

    menu = ctx.get("menu_hoy")
    return {
        "reply": prefix + body,
        "intent": intent,
        "suggestions": EXAM_SUGGESTIONS,
        "related_menu": _menu_card(menu) if menu and menu.get("tipo_dia") == "examen" else None,
        "context_card": _exam_card(ctx),
    }


def _handle_menu_economico(message: str, ctx: dict, intent: str) -> dict:
    perfil = ctx.get("perfil") or {}
    entities = ctx.get("_entities") or {}
    ppto = perfil.get("presupuesto_diario")
    monto_ref = entities.get("monto") or ppto

    reply = (
        "Para comer bien con **presupuesto bajo** te recomiendo:\n\n"
        "🌅 **Desayunos económicos (< $35 MXN):**\n"
        "• Avena con plátano y miel (~$25)\n"
        "• Huevos con tortilla y frijoles (~$30)\n"
        "• Smoothie verde (~$35)\n\n"
        "☀️ **Almuerzos asequibles (< $50 MXN):**\n"
        "• Lentejas con arroz y nopales (~$40)\n"
        "• Tacos de frijoles y guacamole (~$40)\n"
        "• Arroz con frijoles negros y plátano (~$35)\n\n"
        "🌙 **Cenas económicas (< $45 MXN):**\n"
        "• Sopa de verduras ligera (~$30)\n"
        "• Frijoles de olla con arroz (~$35)\n"
        "• Tacos de verduras rostizadas (~$40)\n\n"
        "🍎 **Snacks baratos (< $20 MXN):**\n"
        "• Fruta de temporada (~$15)\n"
        "• Pepino con limón (~$10)\n"
        "• Agua de jamaica (~$10)\n\n"
    )

    if monto_ref:
        if monto_ref < 100:
            reply += (
                f"Con **${monto_ref:.0f} MXN/día** puedes comer bastante bien eligiendo "
                "desayunos tipo avena o huevos, almuerzo de lentejas o frijoles, y una cena ligera."
            )
        elif monto_ref < 180:
            reply += (
                f"Con **${monto_ref:.0f} MXN/día** tienes buen margen. "
                "Puedes combinar opciones económicas con algunas de proteína animal como pollo."
            )
        else:
            reply += (
                f"Con **${monto_ref:.0f} MXN/día** tienes un presupuesto cómodo "
                "para comer muy bien y variado."
            )
    else:
        reply += "Configura tu presupuesto en tu perfil para ver si tu menú diario cabe en él."

    menu = ctx.get("menu_hoy")
    return {
        "reply": reply,
        "intent": intent,
        "suggestions": BUDGET_SUGGESTIONS,
        "related_menu": _menu_card(menu) if menu else None,
        "context_card": _budget_card(ctx),
    }


def _handle_presupuesto_consulta(message: str, ctx: dict, intent: str) -> dict:
    semana = ctx.get("semana") or {}
    perfil = ctx.get("perfil") or {}
    ppto_diario = perfil.get("presupuesto_diario")
    ppto_semanal = perfil.get("presupuesto_semanal")
    costo_semana = semana.get("costo_total") or 0

    if not ppto_diario:
        reply = (
            "Aún no has configurado tu presupuesto alimentario. "
            "Ve a la sección de **Presupuesto** en tu perfil y configúralo para que pueda "
            "darte seguimiento de tus gastos y ajustar los menús a tu bolsillo."
        )
    else:
        reply = "💰 **Resumen de presupuesto esta semana:**\n\n"
        reply += f"• Presupuesto diario: **${ppto_diario:.0f} MXN**\n"
        if ppto_semanal:
            reply += f"• Presupuesto semanal: **${ppto_semanal:.0f} MXN**\n"
        if costo_semana > 0:
            reply += f"• Gasto estimado esta semana: **${costo_semana:.0f} MXN**\n"
            if ppto_semanal:
                restante = ppto_semanal - costo_semana
                if restante >= 0:
                    reply += f"• Te quedan aprox. **${restante:.0f} MXN** para el resto de la semana ✅"
                else:
                    reply += f"• Has superado tu presupuesto por **${abs(restante):.0f} MXN** ⚠️"
        else:
            reply += "• Sin datos de costo esta semana — genera tus menús para verlos."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": BUDGET_SUGGESTIONS,
        "related_menu": None,
        "context_card": _budget_card(ctx),
    }


def _handle_calorias_consulta(message: str, ctx: dict, intent: str) -> dict:
    if not ctx.get("tiene_perfil"):
        return _sin_perfil(intent)

    semana = ctx.get("semana") or {}
    menu_hoy = ctx.get("menu_hoy")

    reply = "📊 **Tu consumo calórico:**\n\n"

    if menu_hoy:
        consumido = menu_hoy.get("consumido", False)
        cal_hoy = menu_hoy.get("calorias_total") or 0
        cal_obj = menu_hoy.get("calorias_objetivo") or 0
        estado = "Marcado como consumido ✅" if consumido else "Aún no marcado como consumido ⏳"
        reply += f"**Hoy:** {cal_hoy} kcal (objetivo: {cal_obj} kcal) — {estado}\n\n"
    else:
        reply += "**Hoy:** No hay menú generado todavía.\n\n"

    cal_semana    = semana.get("calorias_totales")   or 0
    comidas_cons  = semana.get("comidas_consumidas") or 0
    if cal_semana > 0:
        promedio = cal_semana // max(comidas_cons, 1)
        reply += (
            f"**Esta semana:** {cal_semana} kcal en {comidas_cons} comidas consumidas "
            f"(promedio: {promedio} kcal/comida)"
        )
    else:
        reply += "**Esta semana:** Sin datos de consumo registrados aún."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "Dame snacks para estudiar"],
        "related_menu": _menu_card(menu_hoy) if menu_hoy else None,
        "context_card": None,
    }


def _handle_macros_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre macronutrientes."""
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"

    distribuciones = {
        "Bajar peso":         ("40%", "30%", "30%"),
        "Subir masa":         ("25%", "40%", "35%"),
        "Mejorar rendimiento": ("50%", "30%", "20%"),
        "Mantener":           ("45%", "30%", "25%"),
    }
    carbs, prot, grasas = distribuciones.get(objetivo, ("45%", "30%", "25%"))

    reply = (
        f"📐 **Macronutrientes recomendados para tu objetivo ({objetivo}):**\n\n"
        f"• 🍚 **Carbohidratos:** {carbs} de tus calorías diarias\n"
        f"• 🥩 **Proteínas:** {prot} de tus calorías diarias\n"
        f"• 🥑 **Grasas saludables:** {grasas} de tus calorías diarias\n\n"
        "**Fuentes recomendadas:**\n"
        "• **Carbs:** Arroz, tortilla de maíz, avena, camote, frijoles\n"
        "• **Proteínas:** Pollo, huevo, atún, frijoles, lentejas, yogur griego\n"
        "• **Grasas:** Aguacate, nueces, aceite de oliva, semillas\n\n"
    )

    menu_hoy = ctx.get("menu_hoy")
    if menu_hoy and menu_hoy.get("calorias_total"):
        cal = menu_hoy["calorias_total"]
        reply += f"Tu menú de hoy aporta aprox. **{cal} kcal**."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "¿Cuántas calorías llevo?"],
        "related_menu": _menu_card(menu_hoy) if menu_hoy else None,
        "context_card": None,
    }


def _handle_historial_comida(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre el historial de menús."""
    if not ctx.get("tiene_perfil"):
        return _sin_perfil(intent)

    semana = ctx.get("semana") or {}
    generados        = semana.get("menus_generados")    or 0
    comidas_cons     = semana.get("comidas_consumidas") or 0
    comidas_totales  = semana.get("comidas_totales")    or 0
    cal_semana       = semana.get("calorias_totales")   or 0
    costo_semana     = semana.get("costo_total")        or 0

    if generados == 0:
        reply = (
            "No tienes menús registrados esta semana. "
            "Genera tu primer menú del día desde la pantalla de **Recomendación**."
        )
    else:
        reply = (
            f"📋 **Tu historial de esta semana:**\n\n"
            f"• Menús generados: **{generados}**\n"
            f"• Comidas consumidas: **{comidas_cons}** de **{comidas_totales}**\n"
        )
        if cal_semana > 0:
            reply += f"• Calorías totales consumidas: **{cal_semana} kcal**\n"
            if comidas_cons > 0:
                promedio_cal = cal_semana // max(comidas_cons, 1)
                reply += f"• Promedio por comida: **{promedio_cal} kcal**\n"
        if costo_semana > 0:
            reply += f"• Costo total estimado: **${costo_semana:.0f} MXN**\n"

        if comidas_cons < comidas_totales:
            faltantes = comidas_totales - comidas_cons
            reply += (
                f"\n💡 Te faltan {faltantes} comida(s) por marcar como consumidas. "
                "Hazlo en la pantalla de **Recomendación** para llevar mejor control."
            )

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "¿Cuántas calorías llevo?", "¿Cuánto he gastado?"],
        "related_menu": None,
        "context_card": None,
    }


def _handle_objetivo_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre el objetivo nutricional del usuario."""
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"

    consejos = {
        "Bajar peso": (
            "Para **bajar peso** de forma saludable:\n\n"
            "• Déficit calórico moderado (200–400 kcal/día menos de tu mantenimiento)\n"
            "• Alta proteína para preservar músculo: 1.4–1.8g/kg de peso\n"
            "• Carbohidratos principalmente en el desayuno y almuerzo\n"
            "• Cenas ligeras y bajas en carbohidratos\n"
            "• Mucha fibra (verduras, leguminosas) para saciarte\n\n"
            "**Alimentos estrella:** pollo, huevo, nopales, verduras de hoja, frijoles, avena."
        ),
        "Subir masa": (
            "Para **subir masa muscular**:\n\n"
            "• Superávit calórico moderado (+250–400 kcal sobre mantenimiento)\n"
            "• Alta proteína: 1.6–2.2g/kg de peso corporal\n"
            "• Carbohidratos en las comidas pre y post entrenamiento\n"
            "• No elimines las grasas saludables — apoyan las hormonas\n"
            "• Come cada 3–4 horas para síntesis proteica constante\n\n"
            "**Alimentos estrella:** huevo, pollo, atún, frijoles, arroz, avena, aguacate."
        ),
        "Mejorar rendimiento": (
            "Para **mejorar tu rendimiento académico y físico**:\n\n"
            "• Prioriza carbohidratos complejos como fuente de energía\n"
            "• Come bien antes de exámenes o entrenamientos importantes\n"
            "• Proteína suficiente para recuperación: ~1.4g/kg\n"
            "• Omega-3 para la función cognitiva: nueces, semillas de chía\n"
            "• Hidratación constante: 2–3 litros de agua/día\n\n"
            "**Alimentos estrella:** nueces, avena, salmón/atún, huevo, plátano, agua."
        ),
        "Mantener": (
            "Para **mantener tu peso y salud**:\n\n"
            "• Come en tu nivel de mantenimiento calórico\n"
            "• Variedad de alimentos para cubrir todos los micronutrientes\n"
            "• Distribución equilibrada: ~45% carbs, 30% proteína, 25% grasas\n"
            "• Incluye frutas y verduras en todas las comidas\n"
            "• Actividad física regular complementa tu alimentación\n\n"
            "**Clave:** Consistencia y hábitos sostenibles sobre tiempo."
        ),
    }

    reply = f"🎯 **Tu objetivo actual: {objetivo}**\n\n"
    reply += consejos.get(objetivo, consejos["Mantener"])

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "¿Qué puedo comer con poco presupuesto?"],
        "related_menu": _menu_card(ctx.get("menu_hoy")) if ctx.get("menu_hoy") else None,
        "context_card": None,
    }


def _handle_objetivo_economico(message: str, ctx: dict, intent: str) -> dict:
    """
    Combina objetivo físico con restricción de presupuesto.
    Ejemplo: 'Estoy en volumen y tengo poco presupuesto'
    """
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    entities = ctx.get("_entities") or {}
    monto = entities.get("monto") or perfil.get("presupuesto_diario")

    encabezado = f"Aquí va tu plan económico para **{objetivo}**:\n\n"

    if objetivo == "Subir masa":
        plan = (
            "💪 **Subir masa con presupuesto bajo — es posible:**\n\n"
            "• **Proteína barata:** Huevo (~$5/pieza), atún en lata (~$20), frijoles negros (~$15)\n"
            "• **Carbs económicos:** Arroz (~$10 la ración), tortilla de maíz (~$8), avena (~$15)\n"
            "• **Grasas saludables:** Aguacate pequeño (~$15), cacahuates (~$12)\n\n"
            "🍽️ **Ejemplo de día (~$120 MXN):**\n"
            "• Desayuno: 3 huevos + arroz + frijoles (~$35)\n"
            "• Almuerzo: Atún con tortilla y aguacate (~$45)\n"
            "• Cena: Frijoles con arroz y huevo (~$30)\n"
            "• Snack: Cacahuates naturales (~$12)\n"
        )
    elif objetivo == "Bajar peso":
        plan = (
            "🥗 **Bajar peso con presupuesto bajo — estrategia inteligente:**\n\n"
            "• Alto volumen, pocas calorías: nopales, verduras, caldo de verduras\n"
            "• Proteína económica: huevo, frijoles, atún para mantener músculo\n"
            "• Evita comida chatarra aunque sea barata — poco nutritiva y engorda\n\n"
            "🍽️ **Ejemplo de día (~$90 MXN):**\n"
            "• Desayuno: Avena con plátano y agua (~$25)\n"
            "• Almuerzo: Sopa de verduras con pollo desmenuzado (~$40)\n"
            "• Cena: Nopales con huevo y tortilla (~$25)\n"
        )
    else:
        plan = (
            "🎯 **Alimentarte bien con presupuesto ajustado:**\n\n"
            "• Basa tu dieta en: huevo, frijoles, arroz, avena, tortilla y verduras\n"
            "• Son baratos, nutritivos y cubren todos los macronutrientes\n"
            "• Compra fruta de temporada (más barata y más nutritiva)\n\n"
            "🍽️ **Ejemplo de día (~$100 MXN):**\n"
            "• Desayuno: Avena con fruta (~$25)\n"
            "• Almuerzo: Frijoles con arroz y ensalada (~$40)\n"
            "• Cena: Huevos con tortilla y nopales (~$30)\n"
            "• Snack: Fruta de temporada (~$15)\n"
        )

    reply = encabezado + plan
    if monto:
        reply += f"\n\n💰 Con **${monto:.0f} MXN** al día, este plan cabe perfectamente."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "¿Cuánto he gastado esta semana?"],
        "related_menu": _menu_card(ctx.get("menu_hoy")) if ctx.get("menu_hoy") else None,
        "context_card": _budget_card(ctx),
    }


def _handle_restricciones_consulta(message: str, ctx: dict, intent: str) -> dict:
    """Responde a preguntas sobre restricciones o alergias alimentarias."""
    perfil = ctx.get("perfil") or {}
    dieta = perfil.get("dieta") or "Sin restricciones"
    alergias = perfil.get("alergias") or ""
    entities = ctx.get("_entities") or {}
    dieta_inline = entities.get("dieta")

    dieta_activa = dieta_inline or dieta

    consejos = {
        "vegetariana": (
            "🌱 **Dieta vegetariana:**\n\n"
            "• Proteínas: huevo, frijoles, lentejas, garbanzo, tofu, yogur, queso\n"
            "• Hierro: espinacas, lenteja, frijoles (combínalos con vitamina C para mejor absorción)\n"
            "• B12: huevo, lácteos o suplemento si es necesario\n"
            "• Energía estable: avena, arroz integral, quinoa, camote\n\n"
            "✅ La dieta vegetariana es perfectamente compatible con alto rendimiento académico."
        ),
        "vegana": (
            "🌿 **Dieta vegana:**\n\n"
            "• Proteína completa: combina leguminosas + cereales (frijoles + arroz = proteína completa)\n"
            "• Hierro: espinacas, lentejas, semillas de chía + vitamina C para absorberlo\n"
            "• B12: suplementación necesaria (no hay fuentes vegetales confiables)\n"
            "• Calcio: brócoli, col rizada, bebida de soya o almendras fortificada\n"
            "• Omega-3: nueces, semillas de lino, chía\n\n"
            "⚠️ Consulta con un nutriólogo para asegurar que cubres todos los nutrientes."
        ),
        "sin_gluten": (
            "🌾 **Dieta sin gluten:**\n\n"
            "• Cereales permitidos: arroz, maíz, avena certificada sin gluten, quinoa\n"
            "• Evitar: trigo, centeno, cebada y sus derivados (pan, pasta, cerveza)\n"
            "• Proteínas seguras: huevo, carne, pollo, pescado, leguminosas\n"
            "• Revisa etiquetas: la harina de trigo se esconde en salsas, sopas y más\n\n"
            "✅ La tortilla de maíz es tu aliada — naturalmente libre de gluten."
        ),
        "sin_lactosa": (
            "🥛 **Dieta sin lactosa:**\n\n"
            "• Calcio alternativo: brócoli, col, sardinas (con hueso), bebidas vegetales fortificadas\n"
            "• Opciones seguras: leche sin lactosa, yogur sin lactosa, queso madurado (poca lactosa)\n"
            "• Proteína: huevo, carne, pollo, leguminosas sin afectar la lactosa\n\n"
            "✅ La mayoría de recetas mexicanas pueden adaptarse fácilmente."
        ),
        "Sin restricciones": (
            "No tienes restricciones alimentarias registradas en tu perfil. "
            "Si tienes alguna alergia o intolerancia, actualízala en tu **Perfil nutricional** "
            "para que el sistema la considere al generar tus menús."
        ),
    }

    reply = consejos.get(dieta_activa, consejos["Sin restricciones"])

    if alergias:
        reply += f"\n\n⚠️ **Alergias registradas en tu perfil:** {alergias}"

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "¿Qué puedo comer con poco presupuesto?"],
        "related_menu": None,
        "context_card": None,
    }


def _handle_snacks_estudio(message: str, ctx: dict, intent: str) -> dict:
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()

    reply = "🍎 **Snacks ideales para estudiar:**\n\n"

    if nivel_ppto == "bajo" or perfil.get("tipo_menu_preferido") == "economico":
        reply += (
            "**Opciones económicas:**\n"
            "• Fruta de temporada (~$15) — vitamina C y energía rápida\n"
            "• Pepino con chile y limón (~$10) — hidratante y 0 culpas\n"
            "• Agua de jamaica (~$10) — antioxidantes sin calorías extras\n"
            "• Cacahuates naturales (~$12) — proteína y energía\n\n"
        )
    elif nivel_ppto == "alto":
        reply += (
            "**Opciones premium:**\n"
            "• Mix de nueces y almendras (~$45) — omega-3 para la memoria\n"
            "• Guacamole con jícama (~$30) — grasas saludables para el cerebro\n"
            "• Yogur griego (~$35) — proteína y probióticos\n\n"
        )
    else:
        reply += (
            "• Fruta de temporada — rápida, natural y accesible\n"
            "• Mix de nueces — omega-3, bueno para la memoria\n"
            "• Yogur griego — proteína sostenida\n"
            "• Pepino con limón — hidratante y muy bajo en calorías\n"
            "• Galletas de arroz con hummus — fibra y proteína vegetal\n\n"
        )

    if objetivo in ("Subir masa", "Mejorar rendimiento"):
        reply += "💪 Para tu objetivo, prioriza snacks con proteína: yogur, edamame o nueces."
    elif objetivo == "Bajar peso":
        reply += "🥗 Para tu objetivo, elige snacks bajos en calorías: pepino, fruta o agua de jamaica."
    else:
        reply += "☕ Tip: Evita cafeína excesiva — 1-2 tazas al día es suficiente. Prioriza el agua."

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué comer si tengo examen?", "¿Qué debo comer hoy?"],
        "related_menu": None,
        "context_card": None,
    }


def _handle_explicar_menu(message: str, ctx: dict, intent: str) -> dict:
    menu = ctx.get("menu_hoy")
    if not menu:
        return {
            "reply": "No tengo un menú de hoy para explicar. Ve a **Recomendación** y genera tu menú del día.",
            "intent": intent,
            "suggestions": ["¿Qué debo comer hoy?"],
            "related_menu": None,
            "context_card": None,
        }

    tipo_dia = menu.get("tipo_dia") or "normal"
    tipo_labels = {
        "examen": "día de examen — alimentos ligeros que favorecen la concentración",
        "entrega": "día de entrega — energía estable para trabajar todo el día",
        "alta_carga": "día de alta carga académica — más energía para jornadas largas",
        "descanso": "día de descanso — menú más ligero para recuperación",
        "normal": "día regular — menú balanceado para tu jornada académica",
    }
    motivo = tipo_labels.get(tipo_dia, "día regular")
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"

    reply = (
        f"Tu menú de hoy fue diseñado para un **{motivo}**.\n\n"
        f"🎯 **Tu objetivo:** {objetivo}\n"
    )
    if menu.get("calorias_objetivo"):
        reply += f"🔥 **Calorías objetivo:** {menu['calorias_objetivo']} kcal\n"
    if menu.get("calorias_total"):
        reply += f"📊 **Calorías del menú:** {menu['calorias_total']} kcal\n"
    if menu.get("costo_total_estimado"):
        reply += f"💰 **Costo estimado:** ${menu['costo_total_estimado']:.0f} MXN\n"
    if menu.get("dentro_presupuesto") is True:
        reply += "✅ Dentro de tu presupuesto.\n"
    elif menu.get("dentro_presupuesto") is False:
        reply += "⚠️ Supera tu presupuesto diario.\n"
    if menu.get("mensaje"):
        reply += f"\n💬 {menu['mensaje']}"

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué debo comer hoy?", "Dame snacks para estudiar"],
        "related_menu": _menu_card(menu),
        "context_card": None,
    }


def _handle_menu_semanal(message: str, ctx: dict, intent: str) -> dict:
    perfil = ctx.get("perfil") or {}
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()
    ppto_semanal = perfil.get("presupuesto_semanal")

    reply = (
        "📅 **Plan semanal de alimentación:**\n\n"
        "• **Lunes-Miércoles:** Semana de arranque — menús balanceados con proteína y carbohidratos.\n"
        "• **Jueves-Viernes:** Si tienes exámenes o entregas — menús ligeros para concentración.\n"
        "• **Sábado-Domingo:** Descanso — menús más flexibles y de recuperación.\n\n"
        "**Estrategias de ahorro semanal:**\n"
        "• Prepara frijoles, arroz y verduras desde el domingo.\n"
        "• Compra fruta de temporada (más barata y nutritiva).\n"
        "• Opta por huevos, avena y leguminosas — baratos y nutritivos.\n\n"
    )

    if nivel_ppto == "bajo":
        reply += (
            "**Para tu presupuesto bajo:**\n"
            "Basa tu semana en: avena, frijoles, lentejas, huevos, tortillas y verduras. "
            "Son los alimentos más económicos y completos.\n"
        )
    elif ppto_semanal:
        reply += (
            f"💰 Tu presupuesto semanal es de **${ppto_semanal:.0f} MXN** "
            f"— distribúyelo en ~${ppto_semanal / 7:.0f} MXN por día.\n"
        )

    reply += (
        "\nGenera tu menú diario desde la pantalla de **Recomendación** y el sistema "
        "lo adaptará automáticamente a tu agenda y perfil."
    )

    return {
        "reply": reply,
        "intent": intent,
        "suggestions": ["¿Qué puedo comer con poco presupuesto?", "¿Qué comer si tengo examen?"],
        "related_menu": None,
        "context_card": _budget_card(ctx),
    }


def _handle_consejo_hidratacion(message: str, ctx: dict, intent: str) -> dict:
    return {
        "reply": (
            "💧 **Consejos de hidratación para estudiantes:**\n\n"
            "• Mínimo **2 litros de agua** al día, más en días de examen o ejercicio.\n"
            "• El agua de Jamaica sin azúcar es excelente: antioxidante y muy barata (~$10).\n"
            "• Evita refrescos y bebidas azucaradas — dan energía falsa y generan bajón.\n"
            "• El café está bien con moderación: **máximo 2 tazas al día**.\n"
            "• Señal de buena hidratación: orina de color amarillo claro.\n"
            "• Beber agua mejora la concentración y el rendimiento cognitivo."
        ),
        "intent": intent,
        "suggestions": ["Dame snacks para estudiar", "¿Qué debo comer hoy?"],
        "related_menu": None,
        "context_card": None,
    }


def _handle_consejo_nutricion(message: str, ctx: dict, intent: str) -> dict:
    perfil = ctx.get("perfil") or {}
    objetivo = perfil.get("objetivo") or "Mantener"
    entities = ctx.get("_entities") or {}
    nivel_ppto = (perfil.get("nivel_presupuesto") or "").lower()

    # "Quiero comer mejor pero barato"
    if nivel_ppto == "bajo" or entities.get("monto", 999) < 150:
        return _handle_objetivo_economico("", ctx, intent)

    base = (
        "🥗 **Consejos nutricionales para estudiantes universitarios:**\n\n"
        "• **No te saltes comidas:** mantiene tu energía y concentración estables.\n"
        "• **Desayuna siempre:** es el combustible de la mañana académica.\n"
        "• **Come cada 3-4 horas:** evita el bajón de energía en clases.\n"
        "• **Incluye proteína en cada comida:** huevo, frijoles, pollo, atún o yogur.\n"
        "• **Prefiere carbohidratos complejos:** avena, arroz integral, tortilla de maíz.\n"
        "• **Frutas y verduras diario:** mínimo 3-5 porciones.\n"
    )
    extras = {
        "Bajar peso": "\n🎯 **Para bajar peso:** reduce porciones gradualmente, sin eliminar grupos de alimentos.",
        "Subir masa": "\n💪 **Para subir masa:** aumenta proteína (1.6–2g/kg de peso) y calorías de calidad.",
        "Mejorar rendimiento": "\n⚡ **Para rendimiento:** carbohidratos antes de entrenar, proteína después.",
        "Mantener": "\n✅ **Para mantener:** equilibra macros y escucha las señales de hambre/saciedad.",
    }
    return {
        "reply": base + extras.get(objetivo, ""),
        "intent": intent,
        "suggestions": DEFAULT_SUGGESTIONS[:3],
        "related_menu": None,
        "context_card": None,
    }


def _handle_desconocido(message: str, ctx: dict, intent: str) -> dict:
    msg_lower = message.lower().strip()

    # Detecta si el mensaje parece relacionado con la app pero no fue capturado
    palabras_app = {
        "comer", "comida", "menu", "menú", "caloría", "caloria", "proteína",
        "presupuesto", "dinero", "barato", "examen", "estudiar", "snack",
        "desayuno", "almuerzo", "cena", "nutrición", "dieta", "peso",
    }
    palabras_mensaje = set(re.findall(r'\b\w+\b', msg_lower))
    if palabras_mensaje & palabras_app:
        replies_relacionado = [
            "Creo que tu pregunta es sobre alimentación. ¿Puedes ser más específico? "
            "Por ejemplo: '¿Qué como hoy?', '¿Qué puedo cenar barato?', o 'Dame snacks para estudiar'.",
            "Entiendo que tiene que ver con comida o nutrición. Prueba preguntarme algo más concreto — "
            "puedo ayudarte con menús, presupuesto, calorías o snacks.",
        ]
        return {
            "reply": random.choice(replies_relacionado),
            "intent": intent,
            "suggestions": DEFAULT_SUGGESTIONS[:4],
            "related_menu": None,
            "context_card": None,
        }

    # Mensaje aparentemente no relacionado con la app
    return {
        "reply": (
            "Soy el Asistente NutriCampus, especializado en alimentación y nutrición para estudiantes. "
            "Puedo ayudarte con tu menú del día, presupuesto alimentario, snacks para estudiar, "
            "calorías o consejos de nutrición. ¿En qué te ayudo?"
        ),
        "intent": intent,
        "suggestions": DEFAULT_SUGGESTIONS,
        "related_menu": None,
        "context_card": None,
    }


# ── Helpers de cards ──────────────────────────────────────────────

def _menu_card(menu: Optional[dict]) -> Optional[dict]:
    if not menu:
        return None
    return {
        "tipo": "menu",
        "tipo_dia": menu.get("tipo_dia"),
        "calorias_total": menu.get("calorias_total"),
        "costo_total_estimado": menu.get("costo_total_estimado"),
        "dentro_presupuesto": menu.get("dentro_presupuesto"),
        "consumido": menu.get("consumido"),
    }


def _budget_card(ctx: dict) -> Optional[dict]:
    perfil = ctx.get("perfil") or {}
    semana = ctx.get("semana") or {}
    if not perfil.get("presupuesto_diario"):
        return None
    return {
        "tipo": "presupuesto",
        "presupuesto_diario": perfil.get("presupuesto_diario"),
        "presupuesto_semanal": perfil.get("presupuesto_semanal"),
        "nivel_presupuesto": perfil.get("nivel_presupuesto"),
        "costo_semana": semana.get("costo_total") or 0,
    }


def _exam_card(ctx: dict) -> Optional[dict]:
    if not ctx.get("tiene_examen_pronto") and not ctx.get("tiene_examen_hoy"):
        return None
    eventos = [e for e in (ctx.get("proximos_eventos") or []) if e.get("tipo") == "Examen"]
    if not eventos:
        return None
    return {
        "tipo": "examen",
        "proximo_examen": eventos[0],
        "hoy": ctx.get("tiene_examen_hoy", False),
    }


def _sin_perfil(intent: str) -> dict:
    return {
        "reply": (
            "Primero necesito conocer tu perfil nutricional para darte recomendaciones personalizadas. "
            "Ve a la sección de **Perfil** y completa tus datos (edad, peso, objetivo, etc.)."
        ),
        "intent": intent,
        "suggestions": DEFAULT_SUGGESTIONS[:3],
        "related_menu": None,
        "context_card": None,
    }


# ── Tabla de dispatch ─────────────────────────────────────────────

_HANDLERS = {
    "identidad":              _handle_identidad,
    "saludo":                 _handle_saludo,
    "que_comer_hoy":          _handle_que_comer_hoy,
    "cena_consulta":          _handle_cena_consulta,
    "desayuno_consulta":      _handle_desayuno_consulta,
    "almuerzo_consulta":      _handle_almuerzo_consulta,
    "menu_examen":            _handle_menu_examen,
    "menu_economico":         _handle_menu_economico,
    "presupuesto_consulta":   _handle_presupuesto_consulta,
    "calorias_consulta":      _handle_calorias_consulta,
    "macros_consulta":        _handle_macros_consulta,
    "historial_comida":       _handle_historial_comida,
    "objetivo_consulta":      _handle_objetivo_consulta,
    "restricciones_consulta": _handle_restricciones_consulta,
    "snacks_estudio":         _handle_snacks_estudio,
    "explicar_menu":          _handle_explicar_menu,
    "menu_semanal":           _handle_menu_semanal,
    "consejo_hidratacion":    _handle_consejo_hidratacion,
    "consejo_nutricion":      _handle_consejo_nutricion,
    "desconocido":            _handle_desconocido,
}


def get_suggestions(ctx: dict) -> List[str]:
    """Devuelve sugerencias contextuales para mostrar en el chatbot."""
    if ctx.get("tiene_examen_hoy") or ctx.get("tiene_examen_pronto"):
        return EXAM_SUGGESTIONS
    perfil = ctx.get("perfil") or {}
    if perfil.get("presupuesto_diario") or perfil.get("nivel_presupuesto") == "bajo":
        return BUDGET_SUGGESTIONS
    return DEFAULT_SUGGESTIONS
