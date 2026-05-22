"""
Seeder de datos iniciales.
Se ejecuta en el arranque del servidor y es idempotente:
sólo inserta datos si las tablas están vacías.
"""

import logging
from sqlalchemy.orm import Session
import models
from data.foods_db import FOODS_DB

logger = logging.getLogger(__name__)


def seed_alimentos(db: Session, *, force_reseed: bool = False) -> None:
    """
    Inserta el catálogo de alimentos.

    - Idempotente: omite el seed si ya existen filas y force_reseed es False.
    - force_reseed=True: elimina filas obsoletas y re-inserta todo el catálogo.
      Se usa cuando apply_missing_columns() agregó columnas a la tabla y las
      filas existentes tienen valores de relleno (DEFAULT '') en esas columnas.
    """
    count = db.query(models.Alimento).count()

    if count > 0 and not force_reseed:
        logger.info(
            "Catálogo de alimentos ya existe (%d registros). Omitiendo seed.", count
        )
        return

    if force_reseed and count > 0:
        logger.info(
            "Re-sembrando catálogo de alimentos (esquema actualizado): "
            "eliminando %d filas obsoletas.",
            count,
        )
        db.query(models.Alimento).delete()
        db.commit()

    logger.info("Insertando catálogo de alimentos (%d registros)...", len(FOODS_DB))
    for food in FOODS_DB:
        db.add(models.Alimento(**food))
    db.commit()
    logger.info("Catálogo de alimentos insertado correctamente.")
