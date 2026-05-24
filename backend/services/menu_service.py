"""
Servicio CRUD para MenuDiario y RegistroNutricion.
Centraliza la lógica de negocio separada de los routers.
"""

import json
import logging
from datetime import date, datetime, timezone, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models
from services.recommendation_engine import MotorRecomendacion, MAX_ITEMS_POR_COMIDA
from services import meal_service

logger = logging.getLogger(__name__)

_CAMPOS_MENU = ("desayuno", "almuerzo", "cena", "snacks")


def _as_aware(dt: datetime) -> datetime:
    """
    Normaliza un datetime a timezone-aware (UTC) para poder compararlo sin
    el error 'can't compare offset-naive and offset-aware datetimes'.

    PostgreSQL (columna timezone=True) devuelve fechas aware, pero algún dato
    viejo podría venir naive. Si es naive, se asume UTC.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


# ── Menús diarios ─────────────────────────────────────────────────

def get_menu_hoy(db: Session, id_usuario: int, fecha: Optional[date] = None) -> Optional[models.MenuDiario]:
    """Devuelve el menú existente para el usuario en la fecha indicada (o hoy)."""
    target = fecha or date.today()
    return (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_usuario == id_usuario,
            models.MenuDiario.fecha == target,
        )
        .first()
    )


def _menu_desactualizado(menu: models.MenuDiario, perfil: models.PerfilNutricional) -> bool:
    """
    Decide si un menú guardado quedó obsoleto y debe regenerarse.

    Se considera obsoleto si:
    1. Alguna comida tiene MÁS items de los configurados ahora
       (p.ej. menús viejos guardados con 3 alimentos cuando ahora se usa 1).
    2. El perfil se actualizó DESPUÉS de generarse el menú (cambió presupuesto,
       calorías, dieta, objetivo, etc.) → el menú ya no refleja la config actual.

    Si el menú ya consumido (consumido=True) NO se regenera, para no borrar
    lo que el usuario marcó como comido.
    """
    if getattr(menu, "consumido", False):
        return False

    # 1. Demasiados items por comida (config cambió a menos opciones)
    for campo in _CAMPOS_MENU:
        raw = getattr(menu, campo, None) or "[]"
        try:
            n = len(json.loads(raw))
        except (json.JSONDecodeError, TypeError):
            n = 0
        if n > MAX_ITEMS_POR_COMIDA:
            return True

    # 2. Perfil actualizado después de generar el menú
    gen = getattr(menu, "fecha_generacion", None)
    upd = getattr(perfil, "fecha_actualizacion", None)
    if gen is not None and upd is not None and _as_aware(upd) > _as_aware(gen):
        return True

    return False


def get_or_generate_menu(
    db: Session,
    usuario: models.Usuario,
    perfil: models.PerfilNutricional,
    fecha: Optional[date] = None,
) -> models.MenuDiario:
    """
    Devuelve el menú existente del día, o genera uno nuevo si no existe.
    """
    target = fecha or date.today()
    existing = get_menu_hoy(db, usuario.id_usuario, target)
    if existing and not _menu_desactualizado(existing, perfil):
        return existing

    # No hay menú, o el guardado quedó obsoleto (config/presupuesto cambió,
    # o tiene más items de los que ahora se muestran) → regenerar.
    if existing:
        logger.info(
            "Menú de %s desactualizado para usuario=%s; regenerando.",
            target, usuario.id_usuario,
        )
        _detach_menu_references(db, existing.id_menu)
        db.delete(existing)
        db.commit()

    motor = MotorRecomendacion(db)
    return motor.generar_para_usuario(usuario, perfil, target)


def generate_fresh_menu(
    db: Session,
    usuario: models.Usuario,
    perfil: models.PerfilNutricional,
    fecha: Optional[date] = None,
) -> models.MenuDiario:
    """
    Genera un menú nuevo para el día, eliminando cualquier menú previo
    para esa fecha (regeneración forzada).

    Antes de borrar el menú viejo, limpia las referencias en tablas que
    apuntan a él para evitar FK violations:
    - MenuFeedback: se desliga (id_menu → NULL) preservando el like/dislike
    - RegistroNutricion: se elimina (se rehace si se vuelve a marcar consumido)
    """
    target = fecha or date.today()

    existing = get_menu_hoy(db, usuario.id_usuario, target)
    if existing:
        _detach_menu_references(db, existing.id_menu)
        db.delete(existing)
        db.commit()

    motor = MotorRecomendacion(db)
    return motor.generar_para_usuario(usuario, perfil, target, fresh=True)


def regenerate_single_meal(
    db: Session,
    usuario: models.Usuario,
    perfil: models.PerfilNutricional,
    comida: str,
    fecha: Optional[date] = None,
) -> models.MenuDiario:
    """
    Regenera una sola comida ('desayuno'|'almuerzo'|'cena'|'snacks') del menú
    del día indicado, conservando las demás comidas.

    Si todavía no existe un menú para esa fecha, genera el menú completo
    (no tiene sentido refrescar una comida de un menú inexistente).
    """
    target = fecha or date.today()
    motor = MotorRecomendacion(db)

    existing = get_menu_hoy(db, usuario.id_usuario, target)
    if existing is None:
        # No hay menú aún → generamos uno completo
        return motor.generar_para_usuario(usuario, perfil, target, fresh=True)

    return motor.regenerar_comida(usuario, perfil, existing, comida)


def _detach_menu_references(db: Session, id_menu: int) -> None:
    """
    Limpia las referencias FK hacia un menú antes de borrarlo.

    Esto es necesario porque las FKs creadas por SQLAlchemy en versiones
    anteriores no tienen ON DELETE configurado. Esta función hace
    explícito lo que la BD no maneja automáticamente.
    """
    # MenuFeedback: preservamos el feedback pero desligamos del menú
    db.query(models.MenuFeedback).filter(
        models.MenuFeedback.id_menu == id_menu
    ).update({"id_menu": None}, synchronize_session=False)

    # RegistroNutricion: se borra (es derivado del consumo del menú)
    db.query(models.RegistroNutricion).filter(
        models.RegistroNutricion.id_menu == id_menu
    ).delete(synchronize_session=False)

    db.flush()


def marcar_consumido(
    db: Session,
    id_menu: int,
    id_usuario: int,
    consumido: bool = True,
) -> Optional[models.MenuDiario]:
    """Cambia el estado consumido del menú y crea/elimina el registro de nutrición."""
    menu = (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_menu == id_menu,
            models.MenuDiario.id_usuario == id_usuario,
        )
        .first()
    )
    if not menu:
        return None

    menu.consumido = consumido
    db.commit()

    # Sincronizar con registro de nutrición
    registro = (
        db.query(models.RegistroNutricion)
        .filter(
            models.RegistroNutricion.id_menu == id_menu,
            models.RegistroNutricion.id_usuario == id_usuario,
        )
        .first()
    )

    if consumido and not registro:
        registro = models.RegistroNutricion(
            id_usuario    = id_usuario,
            fecha         = menu.fecha,
            id_menu       = id_menu,
            calorias      = menu.calorias_total,
            proteinas     = menu.proteinas_total,
            grasas        = menu.grasas_total,
            carbohidratos = menu.carbohidratos_total,
        )
        db.add(registro)
        db.commit()
    elif not consumido and registro:
        db.delete(registro)
        db.commit()

    db.refresh(menu)
    return menu


def get_historial(
    db: Session,
    id_usuario: int,
    dias: int = 14,
) -> list[models.MenuDiario]:
    """Devuelve los últimos N días de menús del usuario, del más reciente al más antiguo."""
    desde = date.today() - timedelta(days=dias - 1)
    return (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_usuario == id_usuario,
            models.MenuDiario.fecha >= desde,
        )
        .order_by(models.MenuDiario.fecha.desc())
        .all()
    )


def delete_menu(db: Session, id_menu: int, id_usuario: int) -> bool:
    """Elimina el menú y su registro de nutrición asociado. Devuelve True si existía."""
    menu = (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_menu == id_menu,
            models.MenuDiario.id_usuario == id_usuario,
        )
        .first()
    )
    if not menu:
        return False

    _detach_menu_references(db, id_menu)
    db.delete(menu)
    db.commit()
    return True


# ── Estadísticas ──────────────────────────────────────────────────

def calcular_estadisticas(db: Session, id_usuario: int) -> dict:
    """
    Calcula estadísticas de la semana actual (últimos 7 días).

    A partir de la migración a consumo por comida, el cumplimiento se mide
    contando comidas individuales (desayuno/almuerzo/cena/snacks) en vez
    de menús completos. Un menú solo era "consumido" si TODAS sus comidas
    lo estaban, lo cual era demasiado estricto en la práctica.

    - `comidas_consumidas`: total de comidas marcadas como consumidas en los
      últimos 7 días.
    - `comidas_totales`: total de comidas con items en esos menús (los
      campos vacíos no cuentan; un menú sin snacks no penaliza).
    - `tasa_cumplimiento`: comidas_consumidas / comidas_totales.
    - `promedio_calorias`: promedio diario de calorías realmente consumidas
      (solo de las comidas marcadas, no del menú entero). Solo entran al
      promedio los días en los que se consumió al menos una comida.
    """
    historial = get_historial(db, id_usuario, dias=7)

    total = len(historial)
    comidas_consumidas = 0
    comidas_totales    = 0
    cals_consumidas: list[int] = []

    for m in historial:
        c, t = meal_service.contar_comidas(m)
        comidas_consumidas += c
        comidas_totales    += t

        progreso = meal_service.calcular_progreso(m)
        cals_dia = progreso["consumido"]["calorias"]
        if cals_dia > 0:
            cals_consumidas.append(cals_dia)

    tasa = (
        round(comidas_consumidas / comidas_totales, 2)
        if comidas_totales else 0.0
    )
    promedio = (
        int(sum(cals_consumidas) / len(cals_consumidas))
        if cals_consumidas else 0
    )

    return {
        "menus_generados":     total,
        "comidas_consumidas":  comidas_consumidas,
        "comidas_totales":     comidas_totales,
        "tasa_cumplimiento":   tasa,
        "promedio_calorias":   promedio,
        "historial":           historial,
    }
