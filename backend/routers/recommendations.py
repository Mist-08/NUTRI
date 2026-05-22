"""
Endpoints de recomendaciones nutricionales.

GET  /recommendations/today    → Menú del día (genera si no existe)
POST /recommendations/generate → Fuerza regeneración del menú del día
"""

from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import models
import schemas
from database import get_db
from routers.users import get_current_user
from services import menu_service

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


def _get_perfil_o_error(db: Session, id_usuario: int) -> models.PerfilNutricional:
    """Devuelve el perfil nutricional o lanza 400 si no existe."""
    perfil = (
        db.query(models.PerfilNutricional)
        .filter(models.PerfilNutricional.id_usuario == id_usuario)
        .first()
    )
    if not perfil:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Completa tu perfil nutricional para recibir recomendaciones personalizadas",
        )
    return perfil


def _parse_fecha(fecha_str: Optional[str]) -> Optional[date]:
    if not fecha_str:
        return None
    try:
        return date.fromisoformat(fecha_str)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Formato de fecha inválido. Usa YYYY-MM-DD",
        )


@router.get("/today", response_model=schemas.MenuDiarioResponse)
async def get_today_recommendation(
    fecha: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """
    Devuelve el menú del día del usuario.
    Si todavía no existe uno para la fecha indicada (o hoy), lo genera automáticamente.
    """
    perfil     = _get_perfil_o_error(db, current_user.id_usuario)
    fecha_obj  = _parse_fecha(fecha)
    menu       = menu_service.get_or_generate_menu(db, current_user, perfil, fecha_obj)
    return schemas.MenuDiarioResponse.model_validate(menu)


@router.post("/generate", response_model=schemas.MenuDiarioResponse, status_code=status.HTTP_201_CREATED)
async def generate_recommendation(
    request: schemas.GenerarMenuRequest = None,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """
    Fuerza la generación de un menú nuevo para la fecha indicada,
    reemplazando cualquier menú previo de ese día.
    """
    if request is None:
        request = schemas.GenerarMenuRequest()

    perfil    = _get_perfil_o_error(db, current_user.id_usuario)
    fecha_obj = _parse_fecha(request.fecha)
    menu      = menu_service.generate_fresh_menu(db, current_user, perfil, fecha_obj)
    return schemas.MenuDiarioResponse.model_validate(menu)
