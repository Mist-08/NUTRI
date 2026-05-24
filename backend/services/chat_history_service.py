"""
Servicio de historial del chatbot.

Persiste y recupera los mensajes del asistente, SIEMPRE filtrando por
id_usuario para que jamás se mezclen conversaciones entre usuarios.

Una sola conversación continua por usuario (no hay múltiples sesiones).
"""

import logging
from typing import Optional

from sqlalchemy.orm import Session

import models

logger = logging.getLogger(__name__)

# Cuántos mensajes recientes se le pasan a Gemini como memoria. Acotado para
# no inflar el consumo de tokens. 12 ≈ 6 intercambios usuario↔bot.
MEMORIA_MAX_MENSAJES = 12

# Tope de mensajes que devuelve el historial completo a la pantalla.
HISTORIAL_MAX = 200


def guardar_mensaje(
    db: Session,
    id_usuario: int,
    rol: str,
    texto: str,
    intent: Optional[str] = None,
) -> models.ChatMensaje:
    """Guarda un mensaje ('user' o 'bot') del usuario indicado."""
    msg = models.ChatMensaje(
        id_usuario=id_usuario,
        rol=rol,
        texto=texto,
        intent=intent,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return msg


def guardar_intercambio(
    db: Session,
    id_usuario: int,
    mensaje_usuario: str,
    respuesta_bot: str,
    intent: Optional[str] = None,
) -> None:
    """
    Guarda de un jalón el mensaje del usuario y la respuesta del bot.
    Más eficiente que dos commits separados.
    """
    db.add(models.ChatMensaje(id_usuario=id_usuario, rol="user", texto=mensaje_usuario))
    db.add(models.ChatMensaje(id_usuario=id_usuario, rol="bot", texto=respuesta_bot, intent=intent))
    db.commit()


def obtener_historial(db: Session, id_usuario: int) -> list[models.ChatMensaje]:
    """
    Devuelve TODO el historial del usuario (orden cronológico, más viejo
    primero), acotado a HISTORIAL_MAX. Filtrado por id_usuario.
    """
    return (
        db.query(models.ChatMensaje)
        .filter(models.ChatMensaje.id_usuario == id_usuario)
        .order_by(models.ChatMensaje.id_mensaje.asc())
        .limit(HISTORIAL_MAX)
        .all()
    )


def obtener_memoria(db: Session, id_usuario: int) -> list[dict]:
    """
    Devuelve los últimos MEMORIA_MAX_MENSAJES en orden cronológico, como
    lista de dicts {rol, texto}, para pasarle contexto a Gemini.

    Filtrado por id_usuario: solo la conversación de ESTE usuario.
    """
    recientes = (
        db.query(models.ChatMensaje)
        .filter(models.ChatMensaje.id_usuario == id_usuario)
        .order_by(models.ChatMensaje.id_mensaje.desc())   # últimos primero
        .limit(MEMORIA_MAX_MENSAJES)
        .all()
    )
    # Los traemos en desc para tomar los últimos; los devolvemos en asc.
    recientes.reverse()
    return [{"rol": m.rol, "texto": m.texto} for m in recientes]


def limpiar_historial(db: Session, id_usuario: int) -> int:
    """
    Borra TODO el historial del usuario (botón "limpiar conversación").
    Devuelve cuántos mensajes se borraron. Filtrado por id_usuario.
    """
    n = (
        db.query(models.ChatMensaje)
        .filter(models.ChatMensaje.id_usuario == id_usuario)
        .delete(synchronize_session=False)
    )
    db.commit()
    logger.info("Historial de chat borrado: usuario=%d, mensajes=%d", id_usuario, n)
    return n
