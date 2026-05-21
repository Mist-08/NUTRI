from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional
from datetime import time, date


# ── Registro ─────────────────────────────────────────────────────

class UsuarioCreate(BaseModel):
    """Body que recibe POST /auth/register"""
    nombre:   str
    correo:   EmailStr
    password: str

    @field_validator('password')
    @classmethod
    def password_max_length(cls, v):
        if len(v.encode('utf-8')) > 72:
            raise ValueError('La contraseña no puede tener más de 72 caracteres')
        return v


class UsuarioResponse(BaseModel):
    """Respuesta al crear o consultar un usuario"""
    id_usuario: int
    nombre:     str
    correo:     str
    activo:     bool

    class Config:
        from_attributes = True


# ── Login ─────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    """Body que recibe POST /auth/login"""
    correo:   EmailStr
    password: str


class TokenResponse(BaseModel):
    """Token JWT devuelto al hacer login exitoso"""
    access_token: str
    token_type:   str = "bearer"


# ── Perfil Nutricional ────────────────────────────────────────────

class PerfilCreate(BaseModel):
    """Body que recibe POST /usuarios/perfil"""
    edad:               int
    peso:               float
    altura:             float
    sexo:               str
    nivel_actividad:    str
    objetivo:           str
    alergias:           Optional[str]  = None
    dieta:              Optional[str]  = None
    calorias_diarias:   Optional[int]  = None
    condiciones_medicas: Optional[str] = None
    fecha_nacimiento:   Optional[date] = None  # nullable para perfiles legacy


class PerfilResponse(PerfilCreate):
    """Respuesta al guardar el perfil"""
    id_perfil:  int
    id_usuario: int

    class Config:
        from_attributes = True

    @field_validator('fecha_nacimiento', mode='before')
    @classmethod
    def convert_fecha_nacimiento(cls, v):
        # Si viene como datetime.date desde SQLAlchemy → serializar a "YYYY-MM-DD"
        # Si ya es string o None, dejar tal cual.
        if isinstance(v, date):
            return v.strftime('%Y-%m-%d')
        return v


# ── Materias ──────────────────────────────────────────────────────

class MateriaCreate(BaseModel):
    """Body que recibe POST /materias"""
    nombre:       str
    aula:         Optional[str] = None
    profesor:     Optional[str] = None
    color:        str = '#4CAF50'
    lunes:        bool = False
    martes:       bool = False
    miercoles:    bool = False
    jueves:       bool = False
    viernes:      bool = False
    hora_inicio:  str  # formato "HH:MM"
    hora_fin:     str  # formato "HH:MM"


class MateriaResponse(MateriaCreate):
    id_materia: int
    id_usuario: int
    nombre:     str
    aula:       Optional[str] = None
    profesor:   Optional[str] = None
    color:      str
    lunes:      bool
    martes:     bool
    miercoles:  bool
    jueves:     bool
    viernes:    bool
    hora_inicio: str
    hora_fin:    str

    class Config:
        from_attributes = True

    @field_validator('hora_inicio', 'hora_fin', mode='before')
    @classmethod
    def convert_time(cls, v):
        if isinstance(v, time):
            return v.strftime('%H:%M')
        return v


# ── Eventos Académicos ────────────────────────────────────────────

class EventoCreate(BaseModel):
    """Body que recibe POST /eventos"""
    tipo_evento:  str  # Examen, Entrega
    fecha:        str  # formato "YYYY-MM-DD"
    hora_inicio:  str  # formato "HH:MM"
    hora_fin:     Optional[str] = None
    descripcion:  Optional[str] = None


class EventoResponse(EventoCreate):
    id_evento:  int
    id_usuario: int

    class Config:
        from_attributes = True

    @field_validator('fecha', mode='before')
    @classmethod
    def convert_fecha(cls, v):
        if isinstance(v, date):
            return v.strftime('%Y-%m-%d')
        return v

    @field_validator('hora_inicio', 'hora_fin', mode='before')
    @classmethod
    def convert_hora(cls, v):
        if isinstance(v, time):
            return v.strftime('%H:%M')
        return v
