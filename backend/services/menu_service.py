"""
Servicio CRUD para MenuDiario y RegistroNutricion.
Centraliza la lógica de negocio separada de los routers.
"""

from datetime import date, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models
from services.recommendation_engine import MotorRecomendacion


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
    if existing:
        return existing

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
    """
    historial = get_historial(db, id_usuario, dias=7)

    total    = len(historial)
    consumidos = sum(1 for m in historial if m.consumido)

    cals_consumidas = [
        m.calorias_total or 0
        for m in historial
        if m.consumido and m.calorias_total
    ]
    promedio = int(sum(cals_consumidas) / len(cals_consumidas)) if cals_consumidas else 0
    tasa     = round(consumidos / total, 2) if total else 0.0

    return {
        "menus_generados":   total,
        "menus_consumidos":  consumidos,
        "tasa_cumplimiento": tasa,
        "promedio_calorias": promedio,
        "historial":         historial,
    }
