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
    """
    target = fecha or date.today()

    existing = get_menu_hoy(db, usuario.id_usuario, target)
    if existing:
        db.delete(existing)
        db.commit()

    motor = MotorRecomendacion(db)
    return motor.generar_para_usuario(usuario, perfil, target)


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

    registro = (
        db.query(models.RegistroNutricion)
        .filter(models.RegistroNutricion.id_menu == id_menu)
        .first()
    )
    if registro:
        db.delete(registro)

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
