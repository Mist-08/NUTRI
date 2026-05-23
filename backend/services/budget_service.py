"""
Servicio de presupuesto alimentario para NutriCampus AI.

Gestiona la configuración de presupuesto del usuario y calcula
estadísticas de gasto en base al historial de menús.
"""

from datetime import date, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models
import schemas


def get_budget(db: Session, id_usuario: int) -> Optional[models.PerfilNutricional]:
    return (
        db.query(models.PerfilNutricional)
        .filter(models.PerfilNutricional.id_usuario == id_usuario)
        .first()
    )


def update_budget(
    db: Session,
    id_usuario: int,
    data: schemas.PresupuestoUpdate,
) -> models.PerfilNutricional:
    perfil = (
        db.query(models.PerfilNutricional)
        .filter(models.PerfilNutricional.id_usuario == id_usuario)
        .first()
    )
    if not perfil:
        raise ValueError("Perfil nutricional no encontrado")

    if data.presupuesto_diario is not None:
        perfil.presupuesto_diario = data.presupuesto_diario
        # Auto-calcular semanal si no se provee
        if data.presupuesto_semanal is None:
            perfil.presupuesto_semanal = round(data.presupuesto_diario * 7, 2)
    if data.presupuesto_semanal is not None:
        perfil.presupuesto_semanal = data.presupuesto_semanal
    if data.nivel_presupuesto is not None:
        perfil.nivel_presupuesto = data.nivel_presupuesto
    if data.tipo_menu_preferido is not None:
        perfil.tipo_menu_preferido = data.tipo_menu_preferido

    db.commit()
    db.refresh(perfil)
    return perfil


def get_budget_stats(
    db: Session,
    id_usuario: int,
    dias: int = 7,
) -> schemas.BudgetStatsResponse:
    hoy = date.today()
    desde = hoy - timedelta(days=dias - 1)

    menus = (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_usuario == id_usuario,
            models.MenuDiario.fecha >= desde,
            models.MenuDiario.fecha <= hoy,
        )
        .all()
    )

    perfil = (
        db.query(models.PerfilNutricional)
        .filter(models.PerfilNutricional.id_usuario == id_usuario)
        .first()
    )

    costos = [m.costo_total_estimado for m in menus if m.costo_total_estimado is not None]
    total = sum(costos)
    promedio = round(total / len(costos), 2) if costos else 0.0
    dentro = sum(1 for m in menus if m.dentro_presupuesto is True)
    fuera  = sum(1 for m in menus if m.dentro_presupuesto is False)

    presupuesto_diario = perfil.presupuesto_diario if perfil else None
    ahorro = None
    if presupuesto_diario and len(costos) > 0:
        ahorro = round(presupuesto_diario * len(costos) - total, 2)

    return schemas.BudgetStatsResponse(
        dias_analizados=dias,
        costo_promedio_diario=promedio,
        costo_total_periodo=round(total, 2),
        dias_dentro_presupuesto=dentro,
        dias_fuera_presupuesto=fuera,
        presupuesto_diario=presupuesto_diario,
        nivel_presupuesto=perfil.nivel_presupuesto if perfil else None,
        ahorro_estimado=ahorro,
    )
