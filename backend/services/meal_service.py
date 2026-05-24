"""
Servicio de comidas individuales: consumir por comida, favoritos y macros.

Trabaja sobre el menú del día (MenuDiario), permitiendo:
- Marcar/desmarcar UNA comida (desayuno/almuerzo/cena/snacks) como consumida.
- Calcular los macros REALMENTE consumidos (suma solo las comidas marcadas).
- Marcar/desmarcar una comida como favorita (guarda la combinación).

Todo filtrado por id_usuario.
"""

import json
import logging
from typing import Optional

from sqlalchemy.orm import Session

import models

logger = logging.getLogger(__name__)

_CAMPOS_MENU = ("desayuno", "almuerzo", "cena", "snacks")


# ── Helpers JSON ───────────────────────────────────────────────────

def _load_dict(raw: Optional[str]) -> dict:
    if not raw:
        return {}
    try:
        d = json.loads(raw)
        return d if isinstance(d, dict) else {}
    except (json.JSONDecodeError, TypeError):
        return {}


def _load_list(raw: Optional[str]) -> list:
    if not raw:
        return []
    try:
        v = json.loads(raw)
        return v if isinstance(v, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


def _get_menu(db: Session, id_menu: int, id_usuario: int) -> Optional[models.MenuDiario]:
    return (
        db.query(models.MenuDiario)
        .filter(
            models.MenuDiario.id_menu == id_menu,
            models.MenuDiario.id_usuario == id_usuario,
        )
        .first()
    )


# ── Macros por comida ──────────────────────────────────────────────

def _macros_de_comida(menu: models.MenuDiario, campo: str) -> dict:
    """Suma los macros de los alimentos de UNA comida del menú."""
    items = _load_list(getattr(menu, campo, None))
    cal = prot = gras = carb = costo = 0.0
    for it in items:
        cal   += it.get("calorias", 0) or 0
        prot  += it.get("proteinas", 0) or 0
        gras  += it.get("grasas", 0) or 0
        carb  += it.get("carbohidratos", 0) or 0
        costo += it.get("costo_estimado", 0) or 0
    return {
        "calorias":      int(cal),
        "proteinas":     round(prot, 1),
        "grasas":        round(gras, 1),
        "carbohidratos": round(carb, 1),
        "costo":         round(costo, 2),
    }


def calcular_progreso(menu: models.MenuDiario) -> dict:
    """
    Devuelve el progreso de consumo del día: macros consumidos (solo de las
    comidas marcadas como consumidas) vs el total del menú, y cuánto falta.
    """
    consumidas = _load_dict(menu.comidas_consumidas)

    consumido = {"calorias": 0, "proteinas": 0.0, "grasas": 0.0, "carbohidratos": 0.0}
    total     = {"calorias": 0, "proteinas": 0.0, "grasas": 0.0, "carbohidratos": 0.0}

    for campo in _CAMPOS_MENU:
        m = _macros_de_comida(menu, campo)
        for k in total:
            total[k] += m[k]
        if consumidas.get(campo):
            for k in consumido:
                consumido[k] += m[k]

    restante = {k: round(total[k] - consumido[k], 1) for k in total}
    # Redondeo de calorías a int
    for d in (consumido, total, restante):
        d["calorias"] = int(round(d["calorias"]))

    return {
        "objetivo_calorias": menu.calorias_objetivo,
        "consumido":  consumido,
        "total_menu": total,
        "restante":   restante,
        "comidas_consumidas": {c: bool(consumidas.get(c)) for c in _CAMPOS_MENU},
    }


# ── Marcar comida consumida ────────────────────────────────────────

def marcar_comida_consumida(
    db: Session,
    id_menu: int,
    id_usuario: int,
    comida: str,
    consumida: bool,
) -> Optional[models.MenuDiario]:
    """
    Marca/desmarca UNA comida del menú como consumida. Recalcula el flag global
    `consumido` (True solo si TODAS las comidas con contenido están consumidas)
    y sincroniza el RegistroNutricion con los macros realmente consumidos.
    """
    comida = (comida or "").strip().lower()
    if comida not in _CAMPOS_MENU:
        raise ValueError(f"Comida inválida: '{comida}'. Usa una de: {', '.join(_CAMPOS_MENU)}")

    menu = _get_menu(db, id_menu, id_usuario)
    if not menu:
        return None

    consumidas = _load_dict(menu.comidas_consumidas)
    consumidas[comida] = bool(consumida)
    menu.comidas_consumidas = json.dumps(consumidas, ensure_ascii=False)

    # El flag global queda True solo si todas las comidas CON contenido están consumidas
    comidas_con_items = [c for c in _CAMPOS_MENU if _load_list(getattr(menu, c, None))]
    menu.consumido = bool(comidas_con_items) and all(
        consumidas.get(c) for c in comidas_con_items
    )

    db.commit()

    # Sincronizar RegistroNutricion con lo realmente consumido
    _sync_registro(db, menu, id_usuario)

    db.refresh(menu)
    return menu


def _sync_registro(db: Session, menu: models.MenuDiario, id_usuario: int) -> None:
    """
    Mantiene el RegistroNutricion del día igual a los macros consumidos.
    Si no hay nada consumido, borra el registro; si hay, lo crea/actualiza.
    """
    progreso = calcular_progreso(menu)
    c = progreso["consumido"]
    algo_consumido = c["calorias"] > 0

    registro = (
        db.query(models.RegistroNutricion)
        .filter(
            models.RegistroNutricion.id_menu == menu.id_menu,
            models.RegistroNutricion.id_usuario == id_usuario,
        )
        .first()
    )

    if algo_consumido:
        if registro:
            registro.calorias      = c["calorias"]
            registro.proteinas     = c["proteinas"]
            registro.grasas        = c["grasas"]
            registro.carbohidratos = c["carbohidratos"]
        else:
            registro = models.RegistroNutricion(
                id_usuario=id_usuario, fecha=menu.fecha, id_menu=menu.id_menu,
                calorias=c["calorias"], proteinas=c["proteinas"],
                grasas=c["grasas"], carbohidratos=c["carbohidratos"],
            )
            db.add(registro)
        db.commit()
    elif registro:
        db.delete(registro)
        db.commit()


# ── Favoritos por comida ───────────────────────────────────────────

def marcar_comida_favorita(
    db: Session,
    id_menu: int,
    id_usuario: int,
    comida: str,
    favorita: bool,
) -> Optional[models.MenuDiario]:
    """
    Marca/desmarca UNA comida del menú como favorita. Al marcarla, guarda la
    combinación de alimentos en ComidaFavorita (para reaplicarla y darle boost).
    Al desmarcarla, elimina la favorita equivalente.
    """
    comida = (comida or "").strip().lower()
    if comida not in _CAMPOS_MENU:
        raise ValueError(f"Comida inválida: '{comida}'. Usa una de: {', '.join(_CAMPOS_MENU)}")

    menu = _get_menu(db, id_menu, id_usuario)
    if not menu:
        return None

    favs = _load_dict(menu.comidas_favoritas)
    favs[comida] = bool(favorita)
    menu.comidas_favoritas = json.dumps(favs, ensure_ascii=False)

    items = _load_list(getattr(menu, comida, None))
    ids = [it.get("id_alimento") for it in items if it.get("id_alimento") is not None]

    if favorita and ids:
        # Evita duplicar la misma combinación
        existente = _buscar_favorita(db, id_usuario, comida, ids)
        if not existente:
            fav = models.ComidaFavorita(
                id_usuario=id_usuario,
                tipo=comida,
                ids_alimentos=json.dumps(ids, ensure_ascii=False),
                snapshot=json.dumps(items, ensure_ascii=False),
            )
            db.add(fav)
    elif not favorita and ids:
        existente = _buscar_favorita(db, id_usuario, comida, ids)
        if existente:
            db.delete(existente)

    db.commit()
    db.refresh(menu)
    return menu


def _buscar_favorita(db: Session, id_usuario: int, tipo: str, ids: list) -> Optional[models.ComidaFavorita]:
    """Busca una favorita del usuario con el mismo tipo y misma combinación de IDs."""
    favs = (
        db.query(models.ComidaFavorita)
        .filter(
            models.ComidaFavorita.id_usuario == id_usuario,
            models.ComidaFavorita.tipo == tipo,
        )
        .all()
    )
    objetivo = sorted(ids)
    for f in favs:
        if sorted(_load_list(f.ids_alimentos)) == objetivo:
            return f
    return None


def listar_favoritas(db: Session, id_usuario: int) -> list[dict]:
    """Lista las comidas favoritas del usuario (filtrado por id)."""
    favs = (
        db.query(models.ComidaFavorita)
        .filter(models.ComidaFavorita.id_usuario == id_usuario)
        .order_by(models.ComidaFavorita.id_favorita.desc())
        .all()
    )
    out = []
    for f in favs:
        out.append({
            "id_favorita": f.id_favorita,
            "tipo": f.tipo,
            "alimentos": _load_list(f.snapshot),
            "fecha": f.fecha.isoformat() if f.fecha else None,
        })
    return out


def ids_favoritos_por_tipo(db: Session, id_usuario: int, tipo: str) -> set[int]:
    """
    Devuelve el conjunto de IDs de alimentos que aparecen en las comidas
    favoritas del usuario para un tipo dado. Lo usa el motor para dar boost.
    """
    favs = (
        db.query(models.ComidaFavorita)
        .filter(
            models.ComidaFavorita.id_usuario == id_usuario,
            models.ComidaFavorita.tipo == tipo,
        )
        .all()
    )
    ids: set[int] = set()
    for f in favs:
        for i in _load_list(f.ids_alimentos):
            if isinstance(i, int):
                ids.add(i)
    return ids


def eliminar_favorita(db: Session, id_favorita: int, id_usuario: int) -> bool:
    """Elimina una favorita por id (solo si pertenece al usuario)."""
    fav = (
        db.query(models.ComidaFavorita)
        .filter(
            models.ComidaFavorita.id_favorita == id_favorita,
            models.ComidaFavorita.id_usuario == id_usuario,
        )
        .first()
    )
    if not fav:
        return False
    db.delete(fav)
    db.commit()
    return True


# ── Conteo de comidas (para estadísticas) ──────────────────────────

def contar_comidas(menu: models.MenuDiario) -> tuple[int, int]:
    """
    Devuelve (consumidas, totales) para UN menú. Solo se cuentan comidas
    que tienen items (un menú sin snacks no penaliza ni suma al denominador).

    Lo usa el módulo de estadísticas para calcular tasa de cumplimiento a
    nivel de comida individual (no de menú completo).
    """
    consumed_dict = _load_dict(menu.comidas_consumidas)
    totales = consumidas = 0
    for campo in _CAMPOS_MENU:
        if _load_list(getattr(menu, campo, None)):
            totales += 1
            if consumed_dict.get(campo):
                consumidas += 1
    return consumidas, totales
