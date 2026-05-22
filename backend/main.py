import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import engine, Base, SessionLocal
from routers import users
from routers import recommendations, menus

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 1. Crear tablas que no existan todavía.
    Base.metadata.create_all(bind=engine)

    # 2. Agregar columnas faltantes a tablas ya existentes (ALTER TABLE seguro).
    #    Necesario cuando el modelo evoluciona pero create_all() no altera tablas.
    from services.migrations import apply_missing_columns
    altered = apply_missing_columns(engine)

    # 3. Sembrar catálogo de alimentos.
    #    Si la migración alteró 'alimentos', las filas existentes tienen valores
    #    de relleno vacíos → forzar re-seed para poblar correctamente.
    from services.seeder import seed_alimentos
    db = SessionLocal()
    try:
        seed_alimentos(db, force_reseed="alimentos" in altered)
    finally:
        db.close()

    yield  # la aplicación corre aquí


app = FastAPI(
    title="NutriCampus AI API",
    description="Backend para autenticación, perfil nutricional y recomendaciones de menú",
    version="2.0.0",
    lifespan=lifespan,
)

# CORS — permite que Flutter Web y la app móvil se conecten
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # En producción: reemplazar por dominio real
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers existentes
app.include_router(users.router)

# Routers nuevos
app.include_router(recommendations.router)
app.include_router(menus.router)


@app.get("/")
def root():
    return {"message": "NutriCampus AI API corriendo ✅", "version": "2.0.0"}
