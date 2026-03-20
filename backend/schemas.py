from pydantic import BaseModel, EmailStr
from typing import Optional


# ── Registro ────────────────────────────────────────────────────

class UserCreate(BaseModel):
    """Body que recibe el endpoint POST /auth/register"""
    name:     str
    email:    EmailStr
    password: str


class UserResponse(BaseModel):
    """Lo que devuelve el backend al crear un usuario"""
    id:    int
    name:  str
    email: str

    class Config:
        from_attributes = True  # Permite convertir objetos SQLAlchemy


# ── Login ────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    """Body que recibe el endpoint POST /auth/login"""
    email:    EmailStr
    password: str


class TokenResponse(BaseModel):
    """Token JWT que se devuelve al hacer login exitoso"""
    access_token: str
    token_type:   str = "bearer"


# ── Perfil Nutricional ───────────────────────────────────────────

class ProfileCreate(BaseModel):
    """Body que recibe el endpoint POST /users/profile"""
    age:            int
    weight_kg:      float
    height_cm:      float
    gender:         str
    goal:           str
    activity_level: str


class ProfileResponse(ProfileCreate):
    """Lo que devuelve el backend al guardar el perfil"""
    id:      int
    user_id: int

    class Config:
        from_attributes = True
