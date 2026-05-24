"""
Motor de recomendación nutricional de NutriCampus AI.

Analiza el contexto académico del usuario (exámenes, carga de materias)
junto con su perfil nutricional para generar un menú diario personalizado.

Arquitectura híbrida (Fase 2):
- Las REGLAS son la fuente de verdad: filtran restricciones, rankean por
  contexto, presupuesto y objetivo, y calculan macros sobre datos reales del
  catálogo de alimentos.
- GEMINI se llama opcionalmente para refinar la selección y escribir el
  mensaje personalizado. Si Gemini falla (sin internet, sin cuota, key
  inválida) el motor de reglas hace toda la chamba sin que el usuario lo note.
- Los DISLIKES del usuario (tabla menu_feedback) se excluyen al filtrar
  alimentos disponibles.
"""

import json
import random
import logging
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from datetime import date, datetime, timezone, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models
from services import ai_recommendation

logger = logging.getLogger(__name__)

# ── Constantes ────────────────────────────────────────────────────

# Distribución calórica por comida
_CAL_DIST = {
    "Desayuno": 0.25,
    "Almuerzo": 0.35,
    "Cena":     0.30,
    "Snack":    0.10,
}

# Mapeo entre el campo del menú/frontend (minúsculas) y el tipo_comida del
# catálogo de alimentos (capitalizado). El frontend manda 'snacks' pero el
# catálogo usa 'Snack'.
_TIPO_POR_CAMPO = {
    "desayuno": "Desayuno",
    "almuerzo": "Almuerzo",
    "cena":     "Cena",
    "snacks":   "Snack",
}
_CAMPOS_MENU = ("desayuno", "almuerzo", "cena", "snacks")

# Cuántos alimentos mostrar por comida. 1 = una sola opción por comida; si el
# usuario quiere otra, usa el botón de refresh de esa comida.
MAX_ITEMS_POR_COMIDA = 1

# Ajuste calórico según tipo de día
_CAL_FACTOR = {
    "examen":     0.95,   # ligeramente menos para digestión tranquila
    "entrega":    1.00,
    "alta_carga": 1.05,   # más energía para jornada larga
    "normal":     1.00,
    "descanso":   0.90,   # menos actividad física
}

# Mensajes personalizados por contexto (fallback si Gemini no responde)
_MENSAJES = {
    "examen": (
        "Hoy es día de examen. Tu menú está diseñado para mantener tu energía estable "
        "y favorecer la concentración. Evita comidas muy pesadas, mantente hidratado/a "
        "y confía en tu preparación. ¡Tú puedes!"
    ),
    "entrega": (
        "Tienes una entrega importante hoy. Tu menú te ayuda a mantener el foco "
        "y la energía durante todo el día. Tómate descansos cortos y no te olvides de comer."
    ),
    "alta_carga": (
        "Hoy es un día académico intenso. Tu menú tiene más energía para acompañarte "
        "en todas tus clases. Recuerda hidratarte entre sesiones y aprovechar cada descanso."
    ),
    "descanso": (
        "Hoy puedes descansar y recargar energías. Tu menú es más ligero y equilibrado "
        "para que tu cuerpo se recupere. Es buen momento para preparar el cuerpo para la semana."
    ),
    "normal": (
        "Tu menú de hoy está balanceado para mantenerte activo/a y con energía "
        "durante toda la jornada académica. Recuerda comer a horas regulares."
    ),
}

# Mensajes adicionales por objetivo
_MSG_OBJETIVO = {
    "Bajar peso":          " Tu menú tiene un ligero déficit calórico alineado con tu objetivo.",
    "Subir masa":          " El menú prioriza proteína para apoyar tu objetivo de ganar masa muscular.",
    "Mejorar rendimiento": " Los alimentos seleccionados optimizan tu energía y recuperación deportiva.",
    "Mantener":            "",
}

# Alertas contextuales
_ALERTAS_EXAMEN = [
    "💧 Hidratación clave: bebe al menos 2 litros de agua hoy.",
    "🍽️ Come algo ligero 1 hora antes del examen para evitar pesadez.",
    "☕ Modera el café: no más de 1-2 tazas para evitar nerviosismo.",
    "🧠 Los carbohidratos complejos son el combustible de tu cerebro.",
]
_ALERTAS_ALTA_CARGA = [
    "⏰ Intenta comer cada 3-4 horas para mantener la energía estable.",
    "🍱 Prepara snacks fáciles para llevar entre clases.",
    "💧 No esperes a tener sed para hidratarte.",
]
_ALERTAS_CONDICION = {
    "Diabetes":         "⚠️ Menú adaptado: prioriza carbohidratos de bajo índice glucémico.",
    "Hipertensión":     "⚠️ Modera el consumo de sal y alimentos procesados.",
    "Colesterol alto":  "⚠️ Preferimos grasas insaturadas en tu menú de hoy.",
    "Anemia":           "⚠️ Incluimos fuentes de hierro; combínalas con vitamina C.",
    "Gastritis":        "⚠️ Evita comidas muy condimentadas, ácidas o picantes.",
}


# ══════════════════════════════════════════════════════════════════
#  MOTOR DE RECOMENDACIÓN
# ══════════════════════════════════════════════════════════════════

class MotorRecomendacion:

    def __init__(self, db: Session):
        self.db = db
        # Flag para saber si la IA participó en la generación (se guarda en el menú)
        self._ia_used: bool = False
        # Flag para señalar a Gemini que es regeneración → más variedad
        self._fresh: bool = False
        # Mensaje generado por Gemini en la MISMA llamada del menú completo
        # (si está, _generar_mensaje lo usa y no hace otra llamada).
        self._ai_mensaje: Optional[str] = None
        # Razonamientos por comida {tipo: texto} de la llamada del menú completo
        self._ai_razones: dict = {}

    # ── API pública ────────────────────────────────────────────────

    def generar_para_usuario(
        self,
        usuario: models.Usuario,
        perfil: models.PerfilNutricional,
        fecha: Optional[date] = None,
        fresh: bool = False,
    ) -> models.MenuDiario:
        """
        Genera un MenuDiario completo para el usuario en la fecha indicada
        (por defecto hoy), lo persiste en la BD y lo devuelve.

        Args:
            fresh: si True, le pide variedad real a Gemini (mezcla candidatos,
                   sube temperatura). Úsalo en regeneración manual.
        """
        if fecha is None:
            fecha = date.today()

        self._ia_used = False
        self._fresh = fresh
        self._ai_mensaje = None
        self._ai_razones = {}

        # Cargar feedback del usuario para excluir lo que rechazó antes
        disliked_ids   = self._get_disliked_ids(usuario.id_usuario)
        disliked_names = self._get_disliked_names(usuario.id_usuario, disliked_ids)

        contexto = self._analizar_contexto(usuario.id_usuario, fecha)
        cal_obj  = self._calcular_calorias_objetivo(perfil, contexto)

        alimentos   = self._obtener_alimentos()
        disponibles = self._filtrar_por_restricciones(alimentos, perfil, disliked_ids)

        # ── Selección del menú completo en UNA sola llamada a Gemini ─
        #
        # Antes se hacían 4-5 llamadas (una por comida + el mensaje), lo que
        # agotaba rápido la cuota del free tier. Ahora una sola llamada
        # devuelve las 4 comidas + el mensaje del día. Si Gemini falla, cada
        # comida cae al fallback rule-based sin afectar a las demás.
        desayuno, almuerzo, cena, snacks = self._seleccionar_menu_completo(
            disponibles, cal_obj, contexto, perfil, disliked_names,
        )

        todos_items = desayuno + almuerzo + cena + snacks
        totales = self._calcular_totales(todos_items)
        costo_total = round(
            sum((a.costo_estimado or 0.0) for a in todos_items), 2
        )
        presupuesto_diario = perfil.presupuesto_diario

        # Intentar optimizar si se supera el presupuesto
        if presupuesto_diario and costo_total > 0 and costo_total > presupuesto_diario:
            desayuno, almuerzo, cena, snacks = self._optimize_for_budget(
                disponibles, desayuno, almuerzo, cena, snacks,
                presupuesto_diario, cal_obj, contexto, perfil,
            )
            todos_items = desayuno + almuerzo + cena + snacks
            totales = self._calcular_totales(todos_items)
            costo_total = round(sum((a.costo_estimado or 0.0) for a in todos_items), 2)

        dentro_ppto = (
            (costo_total <= presupuesto_diario)
            if presupuesto_diario and costo_total > 0
            else None
        )

        # Mensaje personalizado: intenta Gemini primero, fallback a estático
        mensaje = self._generar_mensaje(
            perfil, contexto, costo_total, dentro_ppto,
            {"Desayuno": desayuno, "Almuerzo": almuerzo, "Cena": cena, "Snack": snacks},
        )

        menu = models.MenuDiario(
            id_usuario           = usuario.id_usuario,
            fecha                = fecha,
            tipo_dia             = contexto["tipo_dia"],
            calorias_objetivo    = cal_obj,
            calorias_total       = totales["calorias"],
            proteinas_total      = totales["proteinas"],
            grasas_total         = totales["grasas"],
            carbohidratos_total  = totales["carbohidratos"],
            desayuno             = json.dumps([self._alimento_a_dict(a) for a in desayuno], ensure_ascii=False),
            almuerzo             = json.dumps([self._alimento_a_dict(a) for a in almuerzo], ensure_ascii=False),
            cena                 = json.dumps([self._alimento_a_dict(a) for a in cena],     ensure_ascii=False),
            snacks               = json.dumps([self._alimento_a_dict(a) for a in snacks],   ensure_ascii=False),
            contexto             = json.dumps(contexto, ensure_ascii=False),
            mensaje              = mensaje,
            alertas              = json.dumps(self._generar_alertas(perfil, contexto), ensure_ascii=False),
            consumido            = False,
            costo_total_estimado = costo_total if costo_total > 0 else None,
            dentro_presupuesto   = dentro_ppto,
            generado_con_ia      = self._ia_used,
            fecha_generacion     = datetime.now(timezone.utc),
            razonamiento_comidas = json.dumps(self._ai_razones, ensure_ascii=False) if self._ai_razones else None,
        )

        self.db.add(menu)
        self.db.commit()
        self.db.refresh(menu)
        return menu

    # ── Regenerar una sola comida (refresh granular) ───────────────

    def regenerar_comida(
        self,
        usuario: models.Usuario,
        perfil: models.PerfilNutricional,
        menu: models.MenuDiario,
        campo: str,
    ) -> models.MenuDiario:
        """
        Regenera UNA sola comida de un menú existente (p.ej. solo la cena),
        dejando las otras 3 intactas, y vuelve a guardar el menú.

        Ventajas sobre regenerar todo el menú:
        - Solo 1 llamada a Gemini en vez de 4-5 → mucho más rápido y dentro
          del timeout del frontend.
        - El usuario conserva las comidas que sí le gustaron.

        Args:
            campo: uno de 'desayuno' | 'almuerzo' | 'cena' | 'snacks'.
        """
        campo = (campo or "").strip().lower()
        if campo not in _TIPO_POR_CAMPO:
            raise ValueError(
                f"Comida inválida: '{campo}'. Usa una de: {', '.join(_CAMPOS_MENU)}"
            )
        tipo = _TIPO_POR_CAMPO[campo]

        # Al refrescar siempre buscamos variedad real
        self._fresh = True
        # Partimos del estado de IA previo del menú; si Gemini participa, sube a True
        self._ia_used = bool(menu.generado_con_ia)

        disliked_ids   = self._get_disliked_ids(usuario.id_usuario)
        disliked_names = self._get_disliked_names(usuario.id_usuario, disliked_ids)

        # Contexto: reusar el guardado en el menú; si no se puede, re-analizar
        contexto: Optional[dict] = None
        if menu.contexto:
            try:
                contexto = json.loads(menu.contexto)
            except (json.JSONDecodeError, TypeError):
                contexto = None
        if contexto is None:
            contexto = self._analizar_contexto(usuario.id_usuario, menu.fecha)

        cal_obj = menu.calorias_objetivo or self._calcular_calorias_objetivo(perfil, contexto)

        alimentos   = self._obtener_alimentos()
        disponibles = self._filtrar_por_restricciones(alimentos, perfil, disliked_ids)

        candidatos, cal_meta = self._rankear_candidatos(
            disponibles, tipo, cal_obj, contexto, perfil,
        )

        # Evitar repetir alimentos que ya están en las OTRAS comidas del menú
        ids_otras = self._ids_en_otras_comidas(menu, excepto=campo)
        candidatos_sin_repetir = [c for c in candidatos if c.id_alimento not in ids_otras]
        # Si excluir deja la lista vacía, usamos los candidatos originales
        candidatos = candidatos_sin_repetir or candidatos

        # Boost de favoritos: si el usuario tiene comidas favoritas de este tipo,
        # los alimentos de esas favoritas suben al frente del ranking.
        candidatos = self._aplicar_boost_favoritos(usuario.id_usuario, campo, candidatos)

        if not candidatos:
            # Sin candidatos para este tipo de comida: dejamos la comida vacía
            nueva: list[models.Alimento] = []
            razonamiento = ""
        else:
            ai_pick, razonamiento = ai_recommendation.pick_meal_with_gemini(
                candidatos=candidatos,
                tipo_comida=tipo,
                cal_meta=cal_meta,
                contexto=contexto,
                perfil=perfil,
                disliked_names=disliked_names,
                max_items=MAX_ITEMS_POR_COMIDA,
                fresh=True,
            )
            if ai_pick:
                self._ia_used = True
                nueva = ai_pick
            else:
                # Sin Gemini el greedy es determinístico y devolvería siempre lo
                # mismo. Barajamos los mejores candidatos para que el refresh
                # varíe igual (manteniendo la pertinencia del ranking).
                nueva = self._seleccionar_greedy(
                    self._barajar_top(candidatos), cal_meta,
                )
                razonamiento = ""

        # Escribir SOLO este campo del menú
        setattr(
            menu, campo,
            json.dumps([self._alimento_a_dict(a) for a in nueva], ensure_ascii=False),
        )

        # Guardar/actualizar el razonamiento de esta comida (por qué cambió)
        self._set_razonamiento_comida(menu, campo, razonamiento)

        # Recalcular totales y costo con las 4 comidas ya actualizadas
        totales, costo_total = self._totales_desde_menu_json(menu)
        menu.calorias_total      = totales["calorias"]
        menu.proteinas_total     = totales["proteinas"]
        menu.grasas_total        = totales["grasas"]
        menu.carbohidratos_total = totales["carbohidratos"]
        menu.costo_total_estimado = costo_total if costo_total > 0 else None

        presupuesto = perfil.presupuesto_diario
        if presupuesto and costo_total > 0:
            menu.dentro_presupuesto = costo_total <= presupuesto
        menu.generado_con_ia = self._ia_used

        self.db.commit()
        self.db.refresh(menu)
        return menu

    def _set_razonamiento_comida(self, menu: models.MenuDiario, campo: str, texto: str) -> None:
        """Guarda/actualiza el razonamiento de una comida en menu.razonamiento_comidas (JSON dict)."""
        try:
            data = json.loads(menu.razonamiento_comidas) if menu.razonamiento_comidas else {}
            if not isinstance(data, dict):
                data = {}
        except (json.JSONDecodeError, TypeError):
            data = {}
        if texto:
            data[campo] = texto
        else:
            data.pop(campo, None)   # sin razonamiento (fallback) → limpiar el viejo
        menu.razonamiento_comidas = json.dumps(data, ensure_ascii=False) if data else None

    def _aplicar_boost_favoritos(self, id_usuario: int, campo: str, candidatos: list) -> list:
        """
        Reordena candidatos poniendo al frente los alimentos que aparecen en las
        comidas favoritas del usuario para este tipo. No filtra (no descarta
        nada), solo prioriza, para que el refresh tienda a reproponer lo que le
        gustó sin perder variedad.
        """
        try:
            from services import meal_service
            fav_ids = meal_service.ids_favoritos_por_tipo(self.db, id_usuario, campo)
        except Exception:
            fav_ids = set()
        if not fav_ids:
            return candidatos
        favoritos = [c for c in candidatos if c.id_alimento in fav_ids]
        resto     = [c for c in candidatos if c.id_alimento not in fav_ids]
        return favoritos + resto

    def _barajar_top(self, candidatos: list, top_n: int = 8) -> list:
        """
        Baraja los primeros `top_n` candidatos (los mejor rankeados) y deja el
        resto en orden. Da variedad al refrescar una comida sin Gemini, sin
        perder pertinencia (no mete candidatos malos al frente).
        """
        if len(candidatos) <= 1:
            return list(candidatos)
        cabeza = list(candidatos[:top_n])
        cola   = list(candidatos[top_n:])
        random.shuffle(cabeza)
        return cabeza + cola

    def _ids_en_otras_comidas(self, menu: models.MenuDiario, excepto: str) -> set[int]:
        """Devuelve los id_alimento presentes en las comidas del menú salvo `excepto`."""
        ids: set[int] = set()
        for campo in _CAMPOS_MENU:
            if campo == excepto:
                continue
            raw = getattr(menu, campo, None) or "[]"
            try:
                for it in json.loads(raw):
                    aid = it.get("id_alimento")
                    if aid is not None:
                        ids.add(aid)
            except (json.JSONDecodeError, TypeError, AttributeError):
                continue
        return ids

    def _totales_desde_menu_json(self, menu: models.MenuDiario) -> tuple[dict, float]:
        """
        Suma calorías/macros/costo leyendo los 4 campos JSON del menú.
        Se usa tras regenerar una comida individual, sin reconstruir objetos ORM.
        """
        cal = prot = gras = carb = costo = 0.0
        for campo in _CAMPOS_MENU:
            raw = getattr(menu, campo, None) or "[]"
            try:
                items = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                items = []
            for it in items:
                cal   += it.get("calorias", 0) or 0
                prot  += it.get("proteinas", 0) or 0
                gras  += it.get("grasas", 0) or 0
                carb  += it.get("carbohidratos", 0) or 0
                costo += it.get("costo_estimado", 0) or 0
        totales = {
            "calorias":      int(cal),
            "proteinas":     round(prot, 1),
            "grasas":        round(gras, 1),
            "carbohidratos": round(carb, 1),
        }
        return totales, round(costo, 2)

    # ── Feedback / Dislikes ────────────────────────────────────────

    def _get_disliked_ids(self, id_usuario: int) -> set[int]:
        """Devuelve el set de id_alimento que el usuario ha marcado como 'dislike'."""
        rows = (
            self.db.query(models.MenuFeedback.id_alimento)
            .filter(
                models.MenuFeedback.id_usuario == id_usuario,
                models.MenuFeedback.tipo == "dislike",
            )
            .distinct()
            .all()
        )
        return {r[0] for r in rows}

    def _get_disliked_names(self, id_usuario: int, disliked_ids: set[int]) -> set[str]:
        """Devuelve los nombres de los alimentos rechazados (para el prompt de Gemini)."""
        if not disliked_ids:
            return set()
        rows = (
            self.db.query(models.Alimento.nombre)
            .filter(models.Alimento.id_alimento.in_(disliked_ids))
            .all()
        )
        return {r[0] for r in rows}

    # ── Contexto académico ─────────────────────────────────────────

    def _analizar_contexto(self, id_usuario: int, fecha: date) -> dict:
        eventos  = self._eventos_del_dia(id_usuario, fecha)
        materias = self._materias_del_dia(id_usuario, fecha)

        tiene_examen  = any(e.tipo_evento == "Examen"   for e in eventos)
        tiene_entrega = any(e.tipo_evento == "Entrega"  for e in eventos)

        horas_clase = sum(
            self._diff_horas(m.hora_inicio, m.hora_fin)
            for m in materias
        )

        # Determinar tipo de día (orden de prioridad)
        es_finde = fecha.weekday() >= 5
        if tiene_examen:
            tipo_dia = "examen"
        elif tiene_entrega and (len(materias) >= 2 or horas_clase >= 3):
            tipo_dia = "alta_carga"
        elif tiene_entrega:
            tipo_dia = "entrega"
        elif es_finde:
            tipo_dia = "descanso"
        elif len(materias) >= 3 or horas_clase >= 5:
            tipo_dia = "alta_carga"
        else:
            tipo_dia = "normal"

        return {
            "tipo_dia":      tipo_dia,
            "tiene_examen":  tiene_examen,
            "tiene_entrega": tiene_entrega,
            "num_clases":    len(materias),
            "horas_clase":   round(horas_clase, 1),
            "eventos":       [e.descripcion or e.tipo_evento for e in eventos],
            "materias":      [m.nombre for m in materias],
        }

    def _eventos_del_dia(self, id_usuario: int, fecha: date) -> list:
        start = datetime.combine(fecha, datetime.min.time())
        end   = datetime.combine(fecha, datetime.max.time())
        return (
            self.db.query(models.EventoAcademico)
            .filter(
                models.EventoAcademico.id_usuario == id_usuario,
                models.EventoAcademico.fecha >= start,
                models.EventoAcademico.fecha <= end,
            )
            .all()
        )

    def _materias_del_dia(self, id_usuario: int, fecha: date) -> list:
        col_map = {
            0: models.Materia.lunes,
            1: models.Materia.martes,
            2: models.Materia.miercoles,
            3: models.Materia.jueves,
            4: models.Materia.viernes,
        }
        weekday = fecha.weekday()
        if weekday not in col_map:
            return []
        return (
            self.db.query(models.Materia)
            .filter(
                models.Materia.id_usuario == id_usuario,
                col_map[weekday] == True,
            )
            .all()
        )

    # ── Calorías y macros ──────────────────────────────────────────

    def _calcular_calorias_objetivo(self, perfil: models.PerfilNutricional, contexto: dict) -> int:
        base = perfil.calorias_diarias or self._calcular_tmb(perfil)
        factor = _CAL_FACTOR.get(contexto["tipo_dia"], 1.0)

        # Ajuste adicional por objetivo
        objetivo = perfil.objetivo or "Mantener"
        if objetivo == "Bajar peso":
            factor *= 0.90
        elif objetivo == "Subir masa":
            factor *= 1.10
        elif objetivo == "Mejorar rendimiento":
            factor *= 1.05

        result = int(base * factor)
        return max(1200, min(result, 4500))   # límites de seguridad

    def _calcular_tmb(self, perfil: models.PerfilNutricional) -> int:
        """Mifflin-St Jeor cuando calorias_diarias no está guardado."""
        if not all([perfil.peso, perfil.altura, perfil.edad]):
            return 2000

        if perfil.sexo == "Masculino":
            tmb = 10 * perfil.peso + 6.25 * perfil.altura - 5 * perfil.edad + 5
        else:
            tmb = 10 * perfil.peso + 6.25 * perfil.altura - 5 * perfil.edad - 161

        factores = {"Bajo": 1.2, "Moderado": 1.55, "Alto": 1.725, "Muy alto": 1.9}
        tdee = tmb * factores.get(perfil.nivel_actividad or "Moderado", 1.2)
        return int(tdee)

    # ── Filtrado por restricciones ─────────────────────────────────

    def _filtrar_por_restricciones(
        self,
        alimentos: list[models.Alimento],
        perfil: models.PerfilNutricional,
        disliked_ids: Optional[set[int]] = None,
    ) -> list[models.Alimento]:
        alergias  = self._parse_csv(perfil.alergias)
        dieta     = (perfil.dieta or "").strip()
        conds     = self._parse_csv(perfil.condiciones_medicas)
        disliked  = disliked_ids or set()

        resultado = []
        for a in alimentos:
            if a.id_alimento in disliked:
                continue
            if not self._cumple_restricciones(a, dieta, alergias, conds):
                continue
            resultado.append(a)

        if not resultado:
            # Si las restricciones + dislikes dejaron la lista vacía, relajamos
            # los dislikes (las restricciones de salud son inviolables).
            logger.warning(
                "No hay alimentos disponibles tras filtrar restricciones+dislikes; "
                "se ignoran los dislikes para no dejar al usuario sin menú."
            )
            return [
                a for a in alimentos
                if self._cumple_restricciones(a, dieta, alergias, conds)
            ] or alimentos

        return resultado

    def _cumple_restricciones(
        self,
        a: models.Alimento,
        dieta: str,
        alergias: set,
        conds: set,
    ) -> bool:
        # Dieta
        if dieta == "Vegetariana" and not a.apto_vegetariano:
            return False
        if dieta == "Vegana" and not a.apto_vegano:
            return False
        if dieta == "Sin gluten" and not a.sin_gluten:
            return False
        if dieta == "Sin lactosa" and not a.sin_lactosa:
            return False

        # Alergias (mapeadas a flags del alimento)
        _ALERGIA_FLAG = {
            "Gluten":       "sin_gluten",
            "Lácteos":      "sin_lactosa",
            "Huevo":        "sin_huevo",
            "Mariscos":     "sin_mariscos",
            "Frutos secos": "sin_frutos_secos",
            "Soya":         "sin_soya",
            "Pescado":      "sin_pescado",
            "Maní":         "sin_mani",
            "Mostaza":      "sin_mostaza",
            "Sésamo":       "sin_sesamo",
        }
        for alergia in alergias:
            flag = _ALERGIA_FLAG.get(alergia)
            if flag and not getattr(a, flag, True):
                return False

        return True

    # ── Selección de alimentos ─────────────────────────────────────

    # Tiempo máximo por comida en la llamada a Gemini (segundos).
    # Si Gemini tarda más, esa comida cae al fallback rule-based.
    GEMINI_TIMEOUT_PER_MEAL = 12.0

    # Tiempo máximo para la llamada del menú completo (1 sola llamada).
    GEMINI_TIMEOUT_MENU = 18.0

    def _seleccionar_menu_completo(
        self,
        disponibles: list[models.Alimento],
        cal_obj: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
        disliked_names: Optional[set[str]] = None,
    ) -> tuple[list, list, list, list]:
        """
        Selecciona las 4 comidas en UNA sola llamada a Gemini (en vez de 4-5).

        1. Rankea candidatos por comida (rápido, en serie, rule-based).
        2. Una llamada a Gemini elige las 4 comidas + escribe el mensaje del día.
        3. Comidas que Gemini no resolvió (o si Gemini falla del todo) caen al
           fallback greedy rule-based.

        Devuelve (desayuno, almuerzo, cena, snacks). El mensaje del día queda
        en self._ai_mensaje para que _generar_mensaje lo use sin otra llamada.
        """
        tipos = ("Desayuno", "Almuerzo", "Cena", "Snack")

        # Paso 1: rankear candidatos por comida (rápido)
        candidatos_por_tipo: dict[str, list[models.Alimento]] = {}
        cal_meta_por_tipo: dict[str, int] = {}
        for tipo in tipos:
            candidatos, cal_meta = self._rankear_candidatos(
                disponibles, tipo, cal_obj, contexto, perfil,
            )
            candidatos_por_tipo[tipo] = candidatos
            cal_meta_por_tipo[tipo] = cal_meta

        # Paso 2: UNA llamada a Gemini para todo el menú (con timeout)
        ai_menu: Optional[dict] = None
        if any(candidatos_por_tipo.values()):
            try:
                with ThreadPoolExecutor(max_workers=1, thread_name_prefix="gemini-menu") as ex:
                    future = ex.submit(
                        ai_recommendation.pick_full_menu_with_gemini,
                        candidatos_por_tipo=candidatos_por_tipo,
                        cal_meta_por_tipo=cal_meta_por_tipo,
                        contexto=contexto,
                        perfil=perfil,
                        disliked_names=disliked_names,
                        max_items=MAX_ITEMS_POR_COMIDA,
                        fresh=self._fresh,
                    )
                    ai_menu = future.result(timeout=self.GEMINI_TIMEOUT_MENU)
            except FuturesTimeout:
                logger.warning(
                    "Gemini timeout en menú completo (>%.0fs), usando fallback rule-based",
                    self.GEMINI_TIMEOUT_MENU,
                )
            except Exception as e:
                logger.warning(
                    "Gemini error en menú completo: %s, usando fallback rule-based", e,
                )

        # Paso 3: armar selección final (Gemini si resolvió esa comida, si no greedy)
        seleccion: dict[str, list[models.Alimento]] = {}
        for tipo in tipos:
            elegidos = ai_menu.get(tipo) if ai_menu else None
            if elegidos:
                self._ia_used = True
                seleccion[tipo] = elegidos
            else:
                seleccion[tipo] = self._seleccionar_greedy(
                    candidatos_por_tipo[tipo], cal_meta_por_tipo[tipo],
                )

        # Mensaje del día generado en la misma llamada (si vino)
        if ai_menu and ai_menu.get("_mensaje"):
            self._ai_mensaje = ai_menu["_mensaje"]
        # Razonamientos por comida (mapeados a los campos del menú)
        if ai_menu and ai_menu.get("_razones"):
            tipo_a_campo = {v: k for k, v in _TIPO_POR_CAMPO.items()}
            for tipo, texto in ai_menu["_razones"].items():
                campo = tipo_a_campo.get(tipo)
                if campo:
                    self._ai_razones[campo] = texto

        return (
            seleccion["Desayuno"],
            seleccion["Almuerzo"],
            seleccion["Cena"],
            seleccion["Snack"],
        )

    # ── Selección de alimentos (paralelizada — respaldo) ───────────

    def _seleccionar_todas_comidas_paralelo(
        self,
        disponibles: list[models.Alimento],
        cal_obj: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
        disliked_names: Optional[set[str]] = None,
    ) -> tuple[list, list, list, list]:
        """
        Selecciona las 4 comidas (Desayuno/Almuerzo/Cena/Snack) en paralelo.

        Estrategia: el ranking rule-based es rápido y se hace en serie. La
        llamada a Gemini es la lenta (red), así que esas 4 llamadas se hacen
        en hilos separados con timeout individual. Si Gemini no está
        disponible o falla en alguna comida, esa comida usa el fallback
        rule-based; las demás siguen.
        """
        tipos = ("Desayuno", "Almuerzo", "Cena", "Snack")

        # Paso 1: rankeo candidatos por comida (rápido, en serie)
        candidatos_por_tipo: dict[str, list[models.Alimento]] = {}
        cal_meta_por_tipo: dict[str, int] = {}
        for tipo in tipos:
            candidatos, cal_meta = self._rankear_candidatos(
                disponibles, tipo, cal_obj, contexto, perfil,
            )
            candidatos_por_tipo[tipo] = candidatos
            cal_meta_por_tipo[tipo] = cal_meta

        # Paso 2: llamar a Gemini para las 4 comidas en paralelo
        # max_workers=4 para no abrir más hilos de los necesarios.
        resultados_ia: dict[str, Optional[list[models.Alimento]]] = {
            t: None for t in tipos
        }

        with ThreadPoolExecutor(max_workers=4, thread_name_prefix="gemini-meal") as ex:
            futures = {
                ex.submit(
                    ai_recommendation.pick_meal_with_gemini,
                    candidatos=candidatos_por_tipo[tipo],
                    tipo_comida=tipo,
                    cal_meta=cal_meta_por_tipo[tipo],
                    contexto=contexto,
                    perfil=perfil,
                    disliked_names=disliked_names,
                    fresh=self._fresh,
                ): tipo
                for tipo in tipos
                if candidatos_por_tipo[tipo]
            }

            for future in futures:
                tipo = futures[future]
                try:
                    resultados_ia[tipo] = future.result(
                        timeout=self.GEMINI_TIMEOUT_PER_MEAL,
                    )
                except FuturesTimeout:
                    logger.warning(
                        "Gemini timeout en %s (>%.0fs), usando fallback rule-based",
                        tipo, self.GEMINI_TIMEOUT_PER_MEAL,
                    )
                    resultados_ia[tipo] = None
                except Exception as e:
                    logger.warning(
                        "Gemini error en %s: %s, usando fallback rule-based",
                        tipo, e,
                    )
                    resultados_ia[tipo] = None

        # Paso 3: para cada comida, usar la selección de Gemini si existe,
        #         o caer al greedy rule-based.
        seleccion_final: dict[str, list[models.Alimento]] = {}
        for tipo in tipos:
            if resultados_ia[tipo]:
                self._ia_used = True
                seleccion_final[tipo] = resultados_ia[tipo]
            else:
                seleccion_final[tipo] = self._seleccionar_greedy(
                    candidatos_por_tipo[tipo],
                    cal_meta_por_tipo[tipo],
                )

        return (
            seleccion_final["Desayuno"],
            seleccion_final["Almuerzo"],
            seleccion_final["Cena"],
            seleccion_final["Snack"],
        )

    def _rankear_candidatos(
        self,
        disponibles: list[models.Alimento],
        tipo: str,
        cal_objetivo_total: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
    ) -> tuple[list[models.Alimento], int]:
        """
        Filtra candidatos por tipo de comida y los ordena por score.
        Devuelve (candidatos_ordenados, cal_meta_para_esta_comida).
        """
        fraccion = _CAL_DIST.get(tipo, 0.25)
        cal_meta = int(cal_objetivo_total * fraccion)

        candidatos = [a for a in disponibles if a.tipo_comida == tipo]
        if not candidatos:
            return [], cal_meta

        # Scoring rule-based
        tipo_dia       = contexto.get("tipo_dia", "normal")
        objetivo       = perfil.objetivo or "Mantener"
        nivel_ppto     = (perfil.nivel_presupuesto or "").lower()
        tipo_menu_pref = (perfil.tipo_menu_preferido or "").lower()

        def score(a: models.Alimento) -> float:
            s = 1.0
            if tipo_dia == "examen" and a.bueno_examen:
                s += 3.0
            if tipo_dia == "alta_carga" and a.alto_rendimiento:
                s += 2.0
            if tipo_dia in ("examen", "descanso") and a.ligero:
                s += 1.5
            if objetivo in ("Subir masa", "Mejorar rendimiento") and a.alta_proteina:
                s += 2.5
            if objetivo == "Bajar peso" and a.ligero:
                s += 2.0
            if objetivo == "Bajar peso" and a.calorias < 300:
                s += 1.0
            costo = a.costo_estimado or 0.0
            if nivel_ppto == "bajo" or tipo_menu_pref == "economico":
                if costo > 0 and costo <= 45.0:
                    s += 2.0
                elif costo > 80.0:
                    s -= 1.5
            elif nivel_ppto == "alto" or tipo_menu_pref == "premium":
                if costo > 70.0:
                    s += 1.0
            return s

        candidatos.sort(key=score, reverse=True)
        return candidatos, cal_meta

    def _seleccionar_greedy(
        self,
        candidatos: list[models.Alimento],
        cal_meta: int,
        max_items: int = MAX_ITEMS_POR_COMIDA,
    ) -> list[models.Alimento]:
        """
        Selección rule-based simple: greedy hasta `max_items` alimentos o hasta
        acercarse al objetivo calórico. Usado como fallback cuando Gemini
        no responde.
        """
        seleccionados: list[models.Alimento] = []
        restante = cal_meta

        for alimento in candidatos:
            if len(seleccionados) >= max_items:
                break
            if alimento.calorias <= restante + 80:   # margen de ±80 kcal
                seleccionados.append(alimento)
                restante -= alimento.calorias

        # Si no se seleccionó nada, forzar el de menor calorías disponible
        if not seleccionados and candidatos:
            seleccionados.append(min(candidatos, key=lambda a: a.calorias))

        return seleccionados

    # ── Selección de alimentos (legacy, una sola comida) ──────────

    def _seleccionar_comida(
        self,
        disponibles: list[models.Alimento],
        tipo: str,
        cal_objetivo_total: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
        disliked_names: Optional[set[str]] = None,
    ) -> list[models.Alimento]:
        """
        Método legacy: selecciona una sola comida (sin paralelizar).
        Conservado por compatibilidad; el flujo principal ahora usa
        _seleccionar_todas_comidas_paralelo.
        """
        candidatos, cal_meta = self._rankear_candidatos(
            disponibles, tipo, cal_objetivo_total, contexto, perfil,
        )
        if not candidatos:
            return []

        ai_pick = ai_recommendation.pick_meal_with_gemini(
            candidatos=candidatos,
            tipo_comida=tipo,
            cal_meta=cal_meta,
            contexto=contexto,
            perfil=perfil,
            disliked_names=disliked_names,
            fresh=self._fresh,
        )
        if ai_pick:
            self._ia_used = True
            return ai_pick

        return self._seleccionar_greedy(candidatos, cal_meta)

    # ── Optimización de presupuesto ───────────────────────────────

    def _optimize_for_budget(
        self,
        disponibles: list,
        desayuno: list,
        almuerzo: list,
        cena: list,
        snacks: list,
        presupuesto: float,
        cal_obj: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
    ) -> tuple:
        """
        Intenta reemplazar los alimentos más caros por alternativas más baratas
        del mismo tipo de comida hasta que el costo total entre en el presupuesto.
        """
        comidas = {
            "Desayuno": list(desayuno),
            "Almuerzo": list(almuerzo),
            "Cena":     list(cena),
            "Snack":    list(snacks),
        }

        for _ronda in range(4):
            costo_actual = sum(
                a.costo_estimado or 0.0
                for grupo in comidas.values()
                for a in grupo
            )
            if costo_actual <= presupuesto:
                break

            # Encontrar el alimento más caro de toda la selección
            mas_caro: Optional[models.Alimento] = None
            tipo_mas_caro = ""
            for tipo, items in comidas.items():
                for a in items:
                    if mas_caro is None or (a.costo_estimado or 0) > (mas_caro.costo_estimado or 0):
                        mas_caro = a
                        tipo_mas_caro = tipo

            if mas_caro is None:
                break

            # Buscar candidato más barato del mismo tipo
            candidatos_baratos = [
                a for a in disponibles
                if a.tipo_comida == tipo_mas_caro
                and a.id_alimento != mas_caro.id_alimento
                and (a.costo_estimado or 0) < (mas_caro.costo_estimado or 0)
            ]
            if not candidatos_baratos:
                break

            # Elegir el más barato disponible con suficientes calorías
            candidatos_baratos.sort(key=lambda a: a.costo_estimado or 0)
            sustituto = candidatos_baratos[0]
            grupo = comidas[tipo_mas_caro]
            idx = next(
                (i for i, a in enumerate(grupo) if a.id_alimento == mas_caro.id_alimento),
                None,
            )
            if idx is not None:
                grupo[idx] = sustituto

        return (
            comidas["Desayuno"],
            comidas["Almuerzo"],
            comidas["Cena"],
            comidas["Snack"],
        )

    # ── Helpers de cálculo ─────────────────────────────────────────

    def _calcular_totales(self, items: list[models.Alimento]) -> dict:
        return {
            "calorias":      sum(a.calorias      for a in items),
            "proteinas":     round(sum(a.proteinas     for a in items), 1),
            "grasas":        round(sum(a.grasas        for a in items), 1),
            "carbohidratos": round(sum(a.carbohidratos for a in items), 1),
        }

    def _alimento_a_dict(self, a: models.Alimento) -> dict:
        # Incluimos id_alimento para que el frontend pueda enviar feedback
        return {
            "id_alimento":    a.id_alimento,
            "nombre":         a.nombre,
            "descripcion":    a.descripcion,
            "porcion":        a.porcion,
            "calorias":       a.calorias,
            "proteinas":      a.proteinas,
            "grasas":         a.grasas,
            "carbohidratos":  a.carbohidratos,
            "beneficios":     a.beneficios,
            "advertencias":   a.advertencias,
            "costo_estimado": a.costo_estimado,
        }

    @staticmethod
    def _diff_horas(inicio, fin) -> float:
        if inicio is None or fin is None:
            return 0.0
        start = inicio.hour * 60 + inicio.minute
        end   = fin.hour   * 60 + fin.minute
        return max(0.0, (end - start) / 60.0)

    @staticmethod
    def _parse_csv(csv_str: Optional[str]) -> set:
        if not csv_str:
            return set()
        return {item.strip() for item in csv_str.split(",") if item.strip()}

    def _obtener_alimentos(self) -> list[models.Alimento]:
        return self.db.query(models.Alimento).all()

    # ── Mensaje y alertas ──────────────────────────────────────────

    # Tiempo máximo para el mensaje personalizado (segundos).
    GEMINI_TIMEOUT_MESSAGE = 8.0

    def _generar_mensaje(
        self,
        perfil: models.PerfilNutricional,
        contexto: dict,
        costo_total: float = 0.0,
        dentro_presupuesto: Optional[bool] = None,
        menu_items: Optional[dict] = None,
    ) -> str:
        """
        Genera el mensaje del día para el menú.

        Si el menú completo se generó con Gemini, el mensaje YA vino en esa
        misma llamada (self._ai_mensaje) → lo usamos sin gastar otra llamada.
        Si no hay mensaje de IA (Gemini no participó), usamos los templates
        estáticos. Así un menú completo cuesta UNA sola llamada a Gemini.
        """
        # Mensaje generado en la misma llamada del menú completo
        if self._ai_mensaje:
            self._ia_used = True
            return self._ai_mensaje

        # Fallback estático (lógica original) — sin llamadas extra a Gemini
        tipo_dia = contexto.get("tipo_dia", "normal")
        msg = _MENSAJES.get(tipo_dia, _MENSAJES["normal"])
        msg += _MSG_OBJETIVO.get(perfil.objetivo or "Mantener", "")

        if costo_total > 0:
            msg += f" Costo estimado del día: ${costo_total:.0f} MXN."
            if dentro_presupuesto is True:
                msg += " Dentro de tu presupuesto diario."
            elif dentro_presupuesto is False:
                msg += " Este menú supera ligeramente tu presupuesto — considera ajustar las porciones."

        return msg

    def _generar_alertas(self, perfil: models.PerfilNutricional, contexto: dict) -> list:
        alertas = []
        tipo_dia = contexto.get("tipo_dia", "normal")

        if tipo_dia == "examen":
            alertas.extend(random.sample(_ALERTAS_EXAMEN, min(2, len(_ALERTAS_EXAMEN))))
        elif tipo_dia == "alta_carga":
            alertas.extend(random.sample(_ALERTAS_ALTA_CARGA, min(2, len(_ALERTAS_ALTA_CARGA))))

        # Alertas por condición médica
        for cond in self._parse_csv(perfil.condiciones_medicas):
            if cond in _ALERTAS_CONDICION:
                alertas.append(_ALERTAS_CONDICION[cond])

        # Alerta de restricciones activas
        alergias = self._parse_csv(perfil.alergias)
        dieta    = (perfil.dieta or "Sin restricciones").strip()
        if alergias or dieta not in ("Sin restricciones", ""):
            alertas.append("✅ Menú adaptado a tus restricciones alimentarias.")

        return alertas
