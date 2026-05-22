"""
Safe startup schema migration helper.

create_all() only creates tables that do not exist — it never alters them.
This module fills that gap: it compares each SQLAlchemy-mapped table against
the live database and issues ALTER TABLE … ADD COLUMN IF NOT EXISTS for every
column that is defined in the model but absent from the database.

No tables are dropped. No data is deleted. Columns are added with safe
defaults so PostgreSQL can backfill existing rows without raising NOT NULL
constraint violations.

Usage (from lifespan, after create_all):
    from services.migrations import apply_missing_columns
    altered = apply_missing_columns(engine)   # returns set of altered table names
"""

import logging
from typing import Optional

from sqlalchemy import Engine, inspect, text

from database import Base

logger = logging.getLogger(__name__)


# ── PostgreSQL type mapping ───────────────────────────────────────────

def _pg_type(col) -> str:
    """Translate a SQLAlchemy column type to a PostgreSQL DDL type string."""
    name = type(col.type).__name__.upper()

    if name in ("VARCHAR", "STRING"):
        length = getattr(col.type, "length", None)
        return f"VARCHAR({length})" if length else "TEXT"
    if name in ("INTEGER", "INT"):
        return "INTEGER"
    if name in ("BIGINTEGER", "BIGINT"):
        return "BIGINT"
    if name in ("FLOAT", "DOUBLE", "DOUBLEPRECISION", "REAL", "NUMERIC"):
        return "DOUBLE PRECISION"
    if name == "BOOLEAN":
        return "BOOLEAN"
    if name == "DATE":
        return "DATE"
    if name in ("DATETIME", "TIMESTAMP"):
        return "TIMESTAMP WITH TIME ZONE"
    if name == "TIME":
        return "TIME"
    # Text / fallback
    return "TEXT"


def _fallback_default(col) -> str:
    """Return a safe SQL literal default for existing rows, by column type."""
    name = type(col.type).__name__.upper()
    if name == "BOOLEAN":
        return "FALSE"
    if name in ("INTEGER", "INT", "BIGINTEGER", "BIGINT", "FLOAT",
                "DOUBLE", "DOUBLEPRECISION", "REAL", "NUMERIC"):
        return "0"
    if name == "DATE":
        return "CURRENT_DATE"
    if name in ("DATETIME", "TIMESTAMP"):
        return "NOW()"
    if name == "TIME":
        return "'00:00:00'"
    return "''"  # VARCHAR / TEXT


def _model_default(col) -> Optional[str]:
    """
    Extract the model-level default as a SQL literal, or None if absent.
    Skips callables (e.g. lambda / func.now) — those are server-side.
    """
    if col.default is not None and not col.default.is_callable:
        val = col.default.arg
        if isinstance(val, bool):
            return "TRUE" if val else "FALSE"
        if isinstance(val, (int, float)):
            return str(val)
        if isinstance(val, str):
            return f"'{val}'"
    return None


def _build_col_ddl(col) -> str:
    """
    Build the DDL fragment that follows ADD COLUMN IF NOT EXISTS <name>.
    Example outputs:
        VARCHAR(30) NOT NULL DEFAULT ''
        BOOLEAN NOT NULL DEFAULT TRUE
        DOUBLE PRECISION
        TEXT
    """
    pg_type = _pg_type(col)

    if col.nullable:
        # Nullable columns need no default — NULL is fine for existing rows.
        return pg_type

    # NOT NULL column: PostgreSQL requires a DEFAULT to backfill existing rows.
    if col.server_default is not None:
        # The DB will handle it via the server-side expression.
        return f"{pg_type} NOT NULL"

    default_val = _model_default(col) or _fallback_default(col)
    return f"{pg_type} NOT NULL DEFAULT {default_val}"


# ── Main entry point ──────────────────────────────────────────────────

def apply_missing_columns(engine: Engine) -> set[str]:
    """
    Inspect every mapped table and add columns that exist in the SQLAlchemy
    model but are absent from the live PostgreSQL database.

    - Uses IF NOT EXISTS so it is safe to run on every startup.
    - Commits all DDL in a single transaction per run.
    - Does NOT drop columns, tables, or any existing data.

    Returns:
        Set of table names that had at least one column added.
    """
    inspector = inspect(engine)
    live_tables: set[str] = set(inspector.get_table_names())
    altered: set[str] = set()

    with engine.connect() as conn:
        for table in Base.metadata.sorted_tables:
            tname = table.name

            if tname not in live_tables:
                # Table is new — create_all() will create it with all columns.
                continue

            live_cols: set[str] = {
                c["name"] for c in inspector.get_columns(tname)
            }

            for col in table.columns:
                if col.name in live_cols:
                    continue  # column already present

                ddl = _build_col_ddl(col)
                stmt = (
                    f'ALTER TABLE "{tname}" '
                    f'ADD COLUMN IF NOT EXISTS "{col.name}" {ddl}'
                )
                logger.info("Migration ▶ %s", stmt)
                conn.execute(text(stmt))
                altered.add(tname)

        if altered:
            conn.commit()

    if altered:
        logger.info(
            "Schema migrations applied to: %s",
            ", ".join(sorted(altered)),
        )
    else:
        logger.info("Schema up to date — no migrations needed.")

    return altered
