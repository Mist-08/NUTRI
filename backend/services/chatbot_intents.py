"""
Detección de intenciones para el chatbot de NutriCampus AI.

Dos capas de detección:
  1. Regex patterns (preciso, alta prioridad)
  2. Topic scoring (semántico, fallback flexible)

Esto permite responder correctamente a mensajes como
"No tengo mucho dinero, qué puedo comer" sin requerir
palabras clave exactas.
"""

import re
from typing import Dict, List, Optional, Tuple

# ── Capa 1: Patterns regex por intención ─────────────────────────

INTENTS: Dict[str, List[str]] = {
    "identidad": [
        r"qui[eé]n\s+(eres|es\s+usted|sos)",
        r"qu[eé]\s+(eres|es\s+esto|haces?)",
        r"c[oó]mo\s+(te\s+llamas|se\s+llama)",
        r"para\s+qu[eé]\s+(sirves|eres)",
        r"qu[eé]\s+puedes\s+(hacer|ayudar)",
        r"present[aá]te",
    ],
    "saludo": [
        r"^(hola|buenos?\s+(d[ií]as?|tardes?|noches?)|qu[eé]\s+tal|hi|hey)[\s!¡]*$",
        r"^(c[oó]mo\s+(est[aá]s?|anda|va))[\s!¡?¿]*$",
    ],
    "menu_examen": [
        r"examen",
        r"prueba\s+(final|parcial)",
        r"antes\s+del\s+examen",
        r"d[ií]a\s+de\s+examen",
        r"rendir\s+(bien|en\s+el)",
        r"concentraci[oó]n",
        r"\bmemoria\b",
        r"comer\s+(para|antes\s+de)\s+(el\s+)?examen",
        r"alimentos?\s+para\s+(la\s+)?concentraci[oó]n",
        r"parcial",
    ],
    "menu_economico": [
        r"\bbarato",
        r"econ[oó]mic",
        r"poco\s+dinero",
        r"poco\s+presupuesto",
        r"no\s+tengo\s+(mucho\s+)?(dinero|lana|efectivo)",
        r"presupuesto\s+(bajo|limitado|poco|ajustado|corto)",
        r"\d+\s*(pesos?|mxn|\$)",
        r"bajos?\s+presupuesto",
        r"\bahorrar\b",
        r"sin\s+gastar",
        r"lo\s+m[aá]s\s+barato",
        r"opci[oó]n\s+(m[aá]s\s+)?econ[oó]mica",
        r"solo\s+tengo",
        r"nada\s+m[aá]s\s+tengo",
        r"alcanzarme",
        r"me\s+alcanza",
    ],
    "presupuesto_consulta": [
        r"cu[aá]nto\s*(he\s+)?gast",
        r"gasto\s+(diario|semanal|de\s+la\s+semana)",
        r"costo\s+(del\s+)?men[uú]",
        r"cu[aá]nto\s+me\s+cuest",
        r"mis\s+gastos",
        r"mi\s+presupuesto\s*(diario|semanal)?",
        r"cu[aá]nto\s+.*presupuesto",
        r"presupuesto\s+(diario|semanal|de\s+(la\s+)?semana)",
        r"ver\s+mi\s+presupuesto",
        r"revisar.*presupuesto",
    ],
    "que_comer_hoy": [
        r"qu[eé]\s*(comer|como|debo\s+comer|puedo\s+comer).*(hoy|d[ií]a)",
        r"qu[eé]\s*(me\s+)?recomiendas?\s*(hoy|para\s+hoy)",
        r"men[uú]\s*(de\s+)?hoy",
        r"qu[eé]\s*tengo\s*(para|de)\s*comer",
        r"qu[eé]\s*me\s+(sugiero|sugier[ae]s?)",
        r"hazme\s+(una\s+)?recomendaci[oó]n",
        r"qu[eé]\s+como\s+hoy",
    ],
    "cena_consulta": [
        r"c[eé]n(ar|a|emos)\b",
        r"para\s+la\s+cena",
        r"qu[eé]\s+.*\bcena\b",
        r"\bcena\b",
    ],
    "desayuno_consulta": [
        r"desayun(ar|o|emos)\b",
        r"para\s+el\s+desayuno",
        r"qu[eé]\s+.*desayu",
        r"\bdesayuno\b",
    ],
    "almuerzo_consulta": [
        r"almorzar|almuerzo",
        r"para\s+el\s+almuerzo",
        r"qu[eé]\s+.*almuer",
        r"\balmuerzo\b",
    ],
    "calorias_consulta": [
        r"cu[aá]ntas?\s+calor[ií]as?\s+(he\s+)?consum",
        r"calor[ií]as?\s+(de\s+)?(hoy|el\s+d[ií]a|esta\s+semana)",
        r"cu[aá]ntas?\s+calor[ií]as?\s+(llevo|tengo|son)",
        r"qu[eé]\s+(he\s+)?comido\s+hoy",
        r"registro\s+(de\s+)?calor[ií]as?",
        r"mi\s+consumo",
        r"calor[ií]as?\s+consumidas?",
    ],
    "macros_consulta": [
        r"\bmacros?\b",
        r"macronutriente",
        r"proteina[s]?\s+(que\s+|he\s+)?(llevo|tengo|consumi)",
        r"cu[aá]nt[ao]\s+proteina",
        r"cu[aá]ntos?\s+carbohidratos?",
        r"carbohidrat",
        r"\bprote[ií]na\b.*\b(llevo|hoy|semana)\b",
    ],
    "historial_comida": [
        r"qu[eé]\s+(he\s+)?comido\s+(esta\s+semana|los\s+[uú]ltimos|esta\s+semana)",
        r"historial\s+(de\s+)?(comidas?|men[uú]s?)",
        r"mis\s+(comidas?|men[uú]s?)\s+(anteriores|pasados?)",
        r"[uú]ltimos\s+men[uú]s?",
        r"semana\s+pasada\s+.*com",
    ],
    "objetivo_consulta": [
        r"mi\s+objetivo",
        r"para\s+(ganar|perder|mantener|subir)\s+(masa|peso|m[uú]sculo)",
        r"en\s+volumen",
        r"\bvolumen\b",
        r"quiero\s+(bajar|subir|perder|ganar)\s+peso",
        r"quiero\s+ganar\s+(masa|m[uú]sculo)",
        r"para\s+mi\s+meta",
        r"qu[eé]\s+(comer|como)\s+para\s+(ganar|perder|bajar|subir)",
    ],
    "restricciones_consulta": [
        r"al[eé]rgico|al[eé]rgi[ac]",
        r"intoleranci",
        r"sin\s+(gluten|lactosa|huevo|mariscos|soya)",
        r"vegetarian[oa]",
        r"vegan[oa]",
        r"no\s+(puedo|debo)\s+comer",
        r"mis\s+restricciones",
        r"alimentos?\s+que\s+(no\s+puedo|debo\s+evitar)",
    ],
    "snacks_estudio": [
        r"\bsnack",
        r"\bbotana\b",
        r"tentempié",
        r"\bmerienda\b",
        r"algo\s+(ligero|peque[ñn]o|r[aá]pido)",
        r"entre\s+comidas?",
        r"mientras\s+estudio",
        r"para\s+estudiar",
        r"concentrarme",
        r"qu[eé]\s+.*\b(snack|botana|merienda)\b",
    ],
    "explicar_menu": [
        r"por\s+qu[eé]\s+(me\s+)?recomend",
        r"por\s+qu[eé]\s+ese\s+men[uú]",
        r"explica.*\bmen[uú]\b",
        r"qu[eé]\s+significa",
        r"qu[eé]\s+(tiene|contiene)\s+(el\s+)?men[uú]",
        r"\bdetalle\b.*\bmen[uú]\b",
        r"informaci[oó]n\s+(del\s+)?men[uú]",
        r"c[oó]mo\s+est[aá]\s+(armado|hecho)\s+(el\s+)?men[uú]",
    ],
    "menu_semanal": [
        r"(plan|men[uú])\s+(semanal|de\s+la\s+semana|para\s+la\s+semana)",
        r"toda\s+la\s+semana",
        r"7\s+d[ií]as",
        r"semana\s+(completa|entera)",
        r"\bplanificar\b",
        r"plan\s+de\s+alimentaci[oó]n",
        r"menú\s+para\s+la\s+semana",
    ],
    "consejo_hidratacion": [
        r"\bagua\b",
        r"hidrat",
        r"\bbeber\b",
        r"tomar\s+l[ií]quidos",
        r"\bsed\b",
        r"cu[aá]nta\s+agua",
    ],
    "consejo_nutricion": [
        r"\bconsejo",
        r"\btips?\b",
        r"recomendaci[oó]n\s+nutricional",
        r"c[oó]mo\s+(mejorar|cuid[ao]r|balancear)\s+(mi\s+)?alimentaci[oó]n",
        r"nutrici[oó]n",
        r"dieta\s+saludable",
        r"comer\s+mejor",
        r"h[aá]bitos?\s+(alimenticio|nutricional|saludable|de\s+comida)",
        r"mejorar\s+(mi\s+)?(dieta|alimentaci[oó]n)",
    ],
}


# ── Capa 2: Topic keywords para matching semántico ───────────────

_TOPIC_KEYWORDS: Dict[str, List[str]] = {
    "economia": [
        "dinero", "pesos", "barato", "barata", "economico", "economica", "precio",
        "costo", "cuesta", "cuestan", "presupuesto", "ahorrar", "poco", "escaso",
        "justo", "ajustado", "alcanza", "alcanzar", "gastado", "gastar", "plata",
        "lana", "efectivo", "recursos", "limitado", "insuficiente", "solo", "nada",
        "apenas", "alcance",
    ],
    "examen": [
        "examen", "examenes", "parcial", "final", "prueba", "pruebas", "concentracion",
        "memoria", "estudiar", "estudios", "rendir", "preparar", "estudio", "presentar",
        "test", "evaluacion",
    ],
    "comida_general": [
        "comer", "comida", "cena", "cenar", "desayuno", "desayunar", "almuerzo",
        "almorzar", "menu", "plato", "alimento", "alimentos", "recomienda", "recomendar",
        "recomendacion", "sugerir", "sugerencia", "opcion", "opciones", "que", "como",
        "como", "comi", "tomar", "ingerir",
    ],
    "snacks": [
        "snack", "snacks", "botana", "botanas", "merienda", "tentempie", "refrigerio",
        "ligero", "ligera", "rapido", "rapida", "pequeño", "entremedio", "mientras",
        "estudio", "concentrar",
    ],
    "calorias": [
        "caloria", "calorias", "kcal", "consumido", "consumir", "registro", "llevo",
        "cuanto", "comido", "ingerido", "energía", "energia",
    ],
    "nutricion": [
        "nutricion", "nutricional", "dieta", "saludable", "sano", "sana", "habito",
        "habitos", "mejor", "mejorar", "balancear", "equilibrio", "proteina", "proteinas",
        "carbohidrato", "carbohidratos", "grasa", "grasas", "macro", "macronutriente",
        "vitamina", "minerales", "fibra",
    ],
    "objetivo": [
        "volumen", "masa", "musculo", "muscular", "perder", "bajar", "subir", "ganar",
        "adelgazar", "engordar", "objetivo", "meta", "rendimiento", "performance",
        "fitness", "gimnasio",
    ],
}


def detect_intent(message: str) -> str:
    """Devuelve la intención principal del mensaje (primera coincidencia en regex)."""
    text = message.lower().strip()
    for intent, patterns in INTENTS.items():
        for pattern in patterns:
            if re.search(pattern, text):
                return intent
    return "desconocido"


def detect_all_intents(message: str) -> List[str]:
    """
    Devuelve todas las intenciones regex detectadas.
    Fundamental para mensajes combinados.
    """
    text = message.lower().strip()
    found: List[str] = []
    for intent, patterns in INTENTS.items():
        for pattern in patterns:
            if re.search(pattern, text):
                found.append(intent)
                break
    return found if found else ["desconocido"]


def topic_score(message: str) -> Dict[str, float]:
    """
    Calcula un score por área temática usando presencia de keywords.
    Permite matching semántico flexible para mensajes no estructurados.

    Ejemplo: "no tengo mucho dinero" → {"economia": 2.0, ...}
    """
    text = message.lower()
    words = set(re.findall(r'\b\w+\b', text))
    scores: Dict[str, float] = {topic: 0.0 for topic in _TOPIC_KEYWORDS}

    for topic, keywords in _TOPIC_KEYWORDS.items():
        for kw in keywords:
            if kw in words:
                scores[topic] += 1.0
            elif len(kw) >= 5 and any(w.startswith(kw[:5]) for w in words):
                scores[topic] += 0.4

    return scores


def dominant_topic(message: str) -> Optional[str]:
    """
    Devuelve el tema dominante si hay señal clara, o None si el mensaje
    es demasiado vago o no relacionado con la app.
    """
    scores = topic_score(message)
    best = max(scores, key=lambda t: scores[t])
    if scores[best] < 0.6:
        return None
    return best


def classify_message(message: str) -> Tuple[List[str], Dict[str, float], Optional[str]]:
    """
    Clasificación completa: intents regex + topic scores + tema dominante.
    Usado por process_message para decidir el handler.
    """
    intents = detect_all_intents(message)
    scores = topic_score(message)
    dominant = dominant_topic(message)
    return intents, scores, dominant


def extract_entities(message: str) -> dict:
    """
    Extrae entidades: montos, referencias temporales, dietas, alergias.
    """
    text = message.lower()
    entities: dict = {}

    # Monto en pesos
    m = re.search(r"(\d+)\s*(pesos?|mxn|\$)", text)
    if m:
        entities["monto"] = int(m.group(1))

    # Referencia temporal
    if re.search(r"pasado\s+ma[ñn]ana", text):
        entities["tiempo"] = "pasado_manana"
    elif re.search(r"\bma[ñn]ana\b", text):
        entities["tiempo"] = "manana"
    elif re.search(r"\bhoy\b", text):
        entities["tiempo"] = "hoy"
    elif re.search(r"esta\s+semana", text):
        entities["tiempo"] = "semana"

    # Dieta
    if re.search(r"vegetarian[oa]", text):
        entities["dieta"] = "vegetariana"
    elif re.search(r"vegan[oa]", text):
        entities["dieta"] = "vegana"
    elif re.search(r"sin\s+gluten", text):
        entities["dieta"] = "sin_gluten"
    elif re.search(r"sin\s+lactosa", text):
        entities["dieta"] = "sin_lactosa"

    # Alergias
    if re.search(r"al[eé]rgi", text):
        entities["tiene_alergia"] = True

    # Objetivo mencionado inline
    if re.search(r"ganar\s+(masa|m[uú]sculo)|volumen|subir\s+peso", text):
        entities["objetivo_inline"] = "subir_masa"
    elif re.search(r"perder|bajar\s+(peso|grasa)|adelgazar", text):
        entities["objetivo_inline"] = "bajar_peso"

    return entities
