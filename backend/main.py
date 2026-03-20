from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base
from routers import users

# Crea todas las tablas en Neon al arrancar (si no existen)
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="NutriCampus AI API",
    description="Backend para autenticación y perfil nutricional",
    version="1.0.0"
)

# CORS — permite que Flutter Web y la app móvil se conecten
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # En producción cambia esto por tu dominio
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registra los endpoints
app.include_router(users.router)


@app.get("/")
def root():
    return {"message": "NutriCampus AI API corriendo ✅"}
