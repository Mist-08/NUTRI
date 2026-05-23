"""
Endpoints del chatbot "Asistente NutriCampus".
"""

import logging

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

import schemas
import models
from database import get_db
from routers.users import get_current_user
from services.chatbot_context_builder import build_context
from services.chatbot_service import process_message, get_suggestions

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/chatbot", tags=["chatbot"])

_FALLBACK_SUGGESTIONS = [
    "¿Qué debo comer hoy?",
    "¿Qué puedo comer con poco presupuesto?",
    "Dame snacks para estudiar",
]


@router.post("/message", response_model=schemas.ChatbotResponse)
def send_message(
    request: schemas.ChatbotMessageRequest,
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Procesa un mensaje y devuelve la respuesta contextual del chatbot."""
    try:
        ctx = build_context(db, current_user.id_usuario)
        result = process_message(request.message, ctx)
        return schemas.ChatbotResponse(**result)
    except Exception:
        logger.exception(
            "Error en /chatbot/message usuario=%d msg=%r",
            current_user.id_usuario,
            request.message[:80],
        )
        return schemas.ChatbotResponse(
            reply=(
                "Tuve un problema al procesar tu mensaje. "
                "Por favor intenta de nuevo en unos segundos."
            ),
            intent="error",
            suggestions=_FALLBACK_SUGGESTIONS,
            related_menu=None,
            context_card=None,
        )


@router.get("/suggestions")
def get_chat_suggestions(
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Devuelve sugerencias contextuales para la pantalla del chatbot."""
    try:
        ctx = build_context(db, current_user.id_usuario)
        return {"suggestions": get_suggestions(ctx)}
    except Exception:
        logger.exception("Error en /chatbot/suggestions usuario=%d", current_user.id_usuario)
        return {"suggestions": _FALLBACK_SUGGESTIONS}


@router.get("/context")
def get_chat_context(
    current_user: models.Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Devuelve el contexto del usuario (útil para debug)."""
    try:
        return build_context(db, current_user.id_usuario)
    except Exception:
        logger.exception("Error en /chatbot/context usuario=%d", current_user.id_usuario)
        return {"error": "No se pudo obtener el contexto"}
