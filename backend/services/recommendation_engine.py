"""
Motor de recomendación nutricional de NutriCampus AI.

Analiza el contexto académico del usuario (exámenes, carga de materias)
junto con su perfil nutricional para generar un menú diario personalizado.
"""

import json
import random
import logging
from datetime import date, datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models

logger = logging.getLogger(__name__)

# ── Constantes ────────────────────────────────────────────────────

# Distribución calórica por comida
_CAL_DIST = {
    "Desayuno": 0.25,
    "Almuerzo": 0.35,
    "Cena":     0.30,
    "Snack":    0.10,
}

# Ajuste calórico según tipo de día
_CAL_FACTOR = {
    "examen":     0.95,   # ligeramente menos para digestión tranquila
    "entrega":    1.00,
    "alta_carga": 1.05,   # más energía para jornada larga
    "normal":     1.00,
    "descanso":   0.90,   # menos actividad física
}

# Mensajes personalizados por contexto
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

    # ── API pública ────────────────────────────────────────────────

    def generar_para_usuario(
        self,
        usuario: models.Usuario,
        perfil: models.PerfilNutricional,
        fecha: Optional[date] = None,
    ) -> models.MenuDiario:
        """
        Genera un MenuDiario completo para el usuario en la fecha indicada
        (por defecto hoy), lo persiste en la BD y lo devuelve.
        """
        if fecha is None:
            fecha = date.today()

        contexto = self._analizar_contexto(usuario.id_usuario, fecha)
        cal_obj   = self._calcular_calorias_objetivo(perfil, contexto)

        alimentos  = self._obtener_alimentos()
        disponibles = self._filtrar_por_restricciones(alimentos, perfil)

        desayuno = self._seleccionar_comida(disponibles, "Desayuno", cal_obj, contexto, perfil)
        almuerzo = self._seleccionar_comida(disponibles, "Almuerzo", cal_obj, contexto, perfil)
        cena     = self._seleccionar_comida(disponibles, "Cena",     cal_obj, contexto, perfil)
        snacks   = self._seleccionar_comida(disponibles, "Snack",    cal_obj, contexto, perfil)

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
            mensaje              = self._generar_mensaje(perfil, contexto, costo_total, dentro_ppto),
            alertas              = json.dumps(self._generar_alertas(perfil, contexto), ensure_ascii=False),
            consumido            = False,
            costo_total_estimado = costo_total if costo_total > 0 else None,
            dentro_presupuesto   = dentro_ppto,
        )

        self.db.add(menu)
        self.db.commit()
        self.db.refresh(menu)
        return menu

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
    ) -> list[models.Alimento]:
        alergias  = self._parse_csv(perfil.alergias)
        dieta     = (perfil.dieta or "").strip()
        conds     = self._parse_csv(perfil.condiciones_medicas)

        resultado = []
        for a in alimentos:
            if not self._cumple_restricciones(a, dieta, alergias, conds):
                continue
            resultado.append(a)

        if not resultado:
            logger.warning(
                "No hay alimentos disponibles tras filtrar restricciones; usando todos."
            )
            return alimentos

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

    def _seleccionar_comida(
        self,
        disponibles: list[models.Alimento],
        tipo: str,
        cal_objetivo_total: int,
        contexto: dict,
        perfil: models.PerfilNutricional,
    ) -> list[models.Alimento]:
        """
        Selecciona 1-3 alimentos del tipo de comida indicado
        para cubrir el presupuesto calórico de esa comida.
        """
        fraccion = _CAL_DIST.get(tipo, 0.25)
        cal_meta = int(cal_objetivo_total * fraccion)

        candidatos = [a for a in disponibles if a.tipo_comida == tipo]
        if not candidatos:
            return []

        # Puntuar candidatos según contexto, objetivo y presupuesto
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
            # Ajuste por presupuesto
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

        seleccionados: list[models.Alimento] = []
        restante = cal_meta

        for alimento in candidatos:
            if len(seleccionados) >= 3:
                break
            if alimento.calorias <= restante + 80:   # margen de ±80 kcal
                seleccionados.append(alimento)
                restante -= alimento.calorias

        # Si no se seleccionó nada, forzar el de menor calorías disponible
        if not seleccionados and candidatos:
            seleccionados.append(min(candidatos, key=lambda a: a.calorias))

        return seleccionados

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
        return {
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

    def _generar_mensaje(
        self,
        perfil: models.PerfilNutricional,
        contexto: dict,
        costo_total: float = 0.0,
        dentro_presupuesto: Optional[bool] = None,
    ) -> str:
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
