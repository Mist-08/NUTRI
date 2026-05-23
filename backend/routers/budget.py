"""
Endpoints de presupuesto alimentario — NutriCampus AI.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import schemas
import models
from database import get_db
from routers.users import get_current_user
from services import budget_service

router = APIRouter(prefix="/nutrition", tags=["presupuesto"])


@router.get("/budget", response_model=schemas.PresupuestoResponse)
def get_budget(
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Obtiene la configuración de presupuesto del usuario."""
    perfil = budget_service.get_budget(db, current_user.id_usuario)
    if not perfil:
        raise HTTPException(status_code=404, detail="Perfil nutricional no encontrado")
    return perfil


@router.put("/budget", response_model=schemas.PresupuestoResponse)
def update_budget(
    data: schemas.PresupuestoUpdate,
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Actualiza la configuración de presupuesto del usuario."""
    try:
        perfil = budget_service.update_budget(db, current_user.id_usuario, data)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return perfil


@router.get("/budget-stats", response_model=schemas.BudgetStatsResponse)
def get_budget_stats(
    dias: int = 7,
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Estadísticas de gasto alimentario de los últimos N días."""
    if dias < 1 or dias > 90:
        raise HTTPException(status_code=400, detail="El parámetro 'dias' debe estar entre 1 y 90")
    return budget_service.get_budget_stats(db, current_user.id_usuario, dias)
