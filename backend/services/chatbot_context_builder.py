"""
Constructor de contexto del usuario para el chatbot de NutriCampus AI.

Recopila información del perfil, presupuesto, menús y eventos
académicos para personalizar las respuestas del chatbot.
"""

import json
from datetime import date, datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

import models


def build_context(db: Session, id_usuario: int) -> dict:
    """
    Construye un diccionario con el contexto completo del usuario.
    Usado por el chatbot para generar respuestas personalizadas.
    """
    hoy = date.today()

    perfil = (
        db.query(models.PerfilNutricional)
        .filter(models.PerfilNutricional.id_usuario == id_usuario)
        .first()
    )

    menu_hoy = (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_usuario == id_usuario,
            models.MenuDiario.fecha == hoy,
        )
        .first()
    )

    # Historial reciente (7 días)
    desde = hoy - timedelta(days=6)
    historial = (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_usuario == id_usuario,
            models.MenuDiario.fecha >= desde,
        )
        .order_by(models.MenuDiario.fecha.desc())
        .all()
    )

    # Próximos eventos (7 días)
    fin_semana = hoy + timedelta(days=7)
    eventos = (
        db.query(models.EventoAcademico)
        .filter(
            models.EventoAcademico.id_usuario == id_usuario,
            models.EventoAcademico.fecha >= datetime.combine(hoy, datetime.min.time()),
            models.EventoAcademico.fecha <= datetime.combine(fin_semana, datetime.max.time()),
        )
        .order_by(models.EventoAcademico.fecha)
        .all()
    )

    # Construir contexto
    ctx: dict = {
        "fecha_hoy": hoy.strftime("%Y-%m-%d"),
        "dia_semana": _dia_semana(hoy),
        "tiene_perfil": perfil is not None,
        "tiene_menu_hoy": menu_hoy is not None,
    }

    if perfil:
        ctx["perfil"] = {
            "objetivo": perfil.objetivo or "Mantener",
            "dieta": perfil.dieta or "Sin restricciones",
            "alergias": perfil.alergias or "",
            "condiciones_medicas": perfil.condiciones_medicas or "",
            "calorias_diarias": perfil.calorias_diarias,
            "presupuesto_diario": perfil.presupuesto_diario,
            "presupuesto_semanal": perfil.presupuesto_semanal,
            "nivel_presupuesto": perfil.nivel_presupuesto,
            "tipo_menu_preferido": perfil.tipo_menu_preferido,
        }
    else:
        ctx["perfil"] = None

    if menu_hoy:
        ctx["menu_hoy"] = {
            "tipo_dia": menu_hoy.tipo_dia,
            "calorias_objetivo": menu_hoy.calorias_objetivo,
            "calorias_total": menu_hoy.calorias_total,
            "costo_total_estimado": menu_hoy.costo_total_estimado,
            "dentro_presupuesto": menu_hoy.dentro_presupuesto,
            "consumido": menu_hoy.consumido,
            "mensaje": menu_hoy.mensaje,
            "desayuno": _parse_comida(menu_hoy.desayuno),
            "almuerzo": _parse_comida(menu_hoy.almuerzo),
            "cena": _parse_comida(menu_hoy.cena),
            "snacks": _parse_comida(menu_hoy.snacks),
        }
    else:
        ctx["menu_hoy"] = None

    # Estadísticas de la semana
    menus_consumidos = [m for m in historial if m.consumido]
    calorias_semana = sum(m.calorias_total or 0 for m in menus_consumidos)
    costo_semana = sum(
        m.costo_total_estimado or 0 for m in historial
        if m.costo_total_estimado is not None
    )

    ctx["semana"] = {
        "menus_generados": len(historial),
        "menus_consumidos": len(menus_consumidos),
        "calorias_totales": calorias_semana,
        "costo_total": round(costo_semana, 2),
    }

    # Próximos eventos académicos
    ctx["proximos_eventos"] = [
        {
            "tipo": e.tipo_evento,
            "fecha": _fecha_str(e.fecha),
            "descripcion": e.descripcion or e.tipo_evento,
        }
        for e in eventos
    ]

    tiene_examen_pronto = any(e.tipo_evento == "Examen" for e in eventos[:3])
    ctx["tiene_examen_pronto"] = tiene_examen_pronto
    ctx["tiene_examen_hoy"] = any(
        e.tipo_evento == "Examen"
        and _as_date(e.fecha) == hoy
        for e in eventos
    )

    return ctx


def _as_date(v) -> date:
    """Normaliza datetime o date a date — Neon puede devolver ambos tipos."""
    if isinstance(v, datetime):
        return v.date()
    return v  # ya es date


def _fecha_str(v) -> str:
    """Formatea datetime o date a 'YYYY-MM-DD'."""
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d")
    return v.isoformat()  # date.isoformat() ya devuelve 'YYYY-MM-DD'


def _parse_comida(json_str: Optional[str]) -> list:
    if not json_str:
        return []
    try:
        return json.loads(json_str)
    except Exception:
        return []


def _dia_semana(d: date) -> str:
    nombres = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
    return nombres[d.weekday()]
