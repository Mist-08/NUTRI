"""
Endpoints de recomendaciones nutricionales.

GET  /recommendations/today    → Menú del día (genera si no existe)
POST /recommendations/generate → Fuerza regeneración del menú del día
POST /recommendations/feedback → Registra like/dislike de un alimento del menú.
                                  Si tipo=dislike y regenerar=true, regenera
                                  el menú excluyendo el alimento rechazado.
"""

import logging
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import models
import schemas
from database import get_db
from routers.users import get_current_user
from services import menu_service

logger = logging.getLogger(__name__)
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


# ── Menú del día ──────────────────────────────────────────────────

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


# ── Feedback (NUEVO en Fase 2) ────────────────────────────────────

@router.post("/feedback", response_model=schemas.FeedbackResponse, status_code=status.HTTP_201_CREATED)
async def submit_feedback(
    request: schemas.FeedbackRequest,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """
    Registra un like o dislike de un alimento específico que apareció en un menú.

    Comportamiento:
    - 'like':    se guarda como señal positiva (usado en fase 3 para boost
                  de popularidad y recomendar a usuarios similares).
    - 'dislike': el alimento se excluirá permanentemente de futuras
                  recomendaciones para este usuario. Si además regenerar=True,
                  el menú actual (o el de la fecha indicada) se regenera al
                  momento, ya sin el alimento rechazado.
    """
    # Validar que el alimento exista
    alimento = (
        db.query(models.Alimento)
        .filter(models.Alimento.id_alimento == request.id_alimento)
        .first()
    )
    if not alimento:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Alimento no encontrado",
        )

    # Si se indica id_menu, validar que pertenece al usuario actual
    if request.id_menu is not None:
        menu_existente = (
            db.query(models.MenuDiario)
            .filter(
                models.MenuDiario.id_menu == request.id_menu,
                models.MenuDiario.id_usuario == current_user.id_usuario,
            )
            .first()
        )
        if not menu_existente:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Menú no encontrado o no pertenece a este usuario",
            )

    # Guardar feedback. Si ya existía uno del MISMO tipo para el mismo
    # alimento, no duplicamos; si existía del OTRO tipo (like ↔ dislike),
    # lo reemplazamos para mantener la última intención del usuario.
    existente = (
        db.query(models.MenuFeedback)
        .filter(
            models.MenuFeedback.id_usuario == current_user.id_usuario,
            models.MenuFeedback.id_alimento == request.id_alimento,
        )
        .order_by(models.MenuFeedback.fecha.desc())
        .first()
    )

    if existente and existente.tipo == request.tipo:
        # Mismo tipo de feedback: solo actualizamos el motivo si llegó nuevo
        if request.motivo:
            existente.motivo = request.motivo
        feedback = existente
        accion = "actualizado"
    elif existente and existente.tipo != request.tipo:
        # Cambio de opinión: borramos el viejo y guardamos el nuevo
        db.delete(existente)
        db.flush()
        feedback = models.MenuFeedback(
            id_usuario  = current_user.id_usuario,
            id_menu     = request.id_menu,
            id_alimento = request.id_alimento,
            tipo        = request.tipo,
            motivo      = request.motivo,
        )
        db.add(feedback)
        accion = "actualizado"
    else:
        feedback = models.MenuFeedback(
            id_usuario  = current_user.id_usuario,
            id_menu     = request.id_menu,
            id_alimento = request.id_alimento,
            tipo        = request.tipo,
            motivo      = request.motivo,
        )
        db.add(feedback)
        accion = "registrado"

    db.commit()
    db.refresh(feedback)

    # Regeneración opcional (solo si es dislike)
    menu_regenerado = None
    mensaje_extra = ""
    if request.tipo == "dislike" and request.regenerar:
        try:
            perfil = _get_perfil_o_error(db, current_user.id_usuario)

            # Si vino id_menu, regeneramos para esa fecha; si no, hoy
            fecha_obj = None
            if request.id_menu is not None:
                menu_viejo = (
                    db.query(models.MenuDiario)
                    .filter(models.MenuDiario.id_menu == request.id_menu)
                    .first()
                )
                if menu_viejo:
                    fecha_obj = menu_viejo.fecha

            nuevo_menu = menu_service.generate_fresh_menu(
                db, current_user, perfil, fecha_obj,
            )
            menu_regenerado = schemas.MenuDiarioResponse.model_validate(nuevo_menu)
            mensaje_extra = " El menú se regeneró excluyendo este alimento."
        except HTTPException:
            # Si falla por falta de perfil, no rompemos el feedback
            mensaje_extra = " (No se pudo regenerar: completa tu perfil primero.)"
        except Exception:
            logger.exception(
                "Error regenerando menú tras dislike para usuario=%d",
                current_user.id_usuario,
            )
            mensaje_extra = " (No se pudo regenerar el menú en este momento.)"

    accion_humana = (
        "guardado"     if accion == "registrado" else
        "actualizado"
    )
    if request.tipo == "like":
        msg = f"¡Bien! Like {accion_humana} para '{alimento.nombre}'.{mensaje_extra}"
    else:
        msg = (
            f"Entendido. No te volveremos a sugerir '{alimento.nombre}'.{mensaje_extra}"
        )

    return schemas.FeedbackResponse(
        id_feedback     = feedback.id_feedback,
        tipo            = feedback.tipo,
        mensaje         = msg,
        menu_regenerado = menu_regenerado,
    )
