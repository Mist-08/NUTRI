"""
Endpoints de gestión de menús y estadísticas.

GET    /menus/history           → Historial de menús (últimos N días)
POST   /menus/{id}/consumed     → Marcar/desmarcar como consumido
DELETE /menus/{id}              → Eliminar menú
GET    /nutrition/stats         → Estadísticas de la semana actual
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import models
import schemas
from database import get_db
from routers.users import get_current_user
from services import menu_service

router = APIRouter(tags=["menus"])


# ── Historial ─────────────────────────────────────────────────────

@router.get("/menus/history", response_model=list[schemas.HistorialMenuResponse])
async def get_menu_history(
    dias: int = 14,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Devuelve los últimos `dias` días de menús generados para el usuario."""
    dias = max(1, min(dias, 90))   # límite seguro: 1-90 días
    menus = menu_service.get_historial(db, current_user.id_usuario, dias)
    return [schemas.HistorialMenuResponse.model_validate(m) for m in menus]


# ── Marcar consumido ──────────────────────────────────────────────

@router.post("/menus/{id_menu}/consumed", response_model=schemas.MenuDiarioResponse)
async def mark_consumed(
    id_menu: int,
    request: schemas.MarcarConsumedoRequest,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Marca o desmarca un menú como consumido y sincroniza el registro de nutrición."""
    menu = menu_service.marcar_consumido(db, id_menu, current_user.id_usuario, request.consumido)
    if not menu:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Menú no encontrado",
        )
    return schemas.MenuDiarioResponse.model_validate(menu)


# ── Eliminar menú ─────────────────────────────────────────────────

@router.delete("/menus/{id_menu}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_menu(
    id_menu: int,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Elimina permanentemente un menú y su registro de nutrición asociado."""
    deleted = menu_service.delete_menu(db, id_menu, current_user.id_usuario)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Menú no encontrado",
        )


# ── Estadísticas ──────────────────────────────────────────────────

@router.get("/nutrition/stats", response_model=schemas.EstadisticasSemana)
async def get_nutrition_stats(
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Devuelve estadísticas nutricionales de los últimos 7 días."""
    stats = menu_service.calcular_estadisticas(db, current_user.id_usuario)
    return schemas.EstadisticasSemana(
        menus_generados   = stats["menus_generados"],
        menus_consumidos  = stats["menus_consumidos"],
        tasa_cumplimiento = stats["tasa_cumplimiento"],
        promedio_calorias = stats["promedio_calorias"],
        historial         = [
            schemas.HistorialMenuResponse.model_validate(m)
            for m in stats["historial"]
        ],
    )
