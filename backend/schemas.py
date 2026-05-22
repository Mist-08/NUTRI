from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional, List
from datetime import time, date, datetime


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


# ── Recomendaciones / Menús ───────────────────────────────────────

class AlimentoEnMenu(BaseModel):
    """Un alimento concreto dentro de una comida del menú"""
    nombre:        str
    descripcion:   Optional[str] = None
    porcion:       str
    calorias:      int
    proteinas:     float
    grasas:        float
    carbohidratos: float
    beneficios:    Optional[str] = None
    advertencias:  Optional[str] = None


class ContextoAcademicoSchema(BaseModel):
    """Resumen del contexto académico del día"""
    tipo_dia:       str
    tiene_examen:   bool
    tiene_entrega:  bool
    num_clases:     int
    horas_clase:    float
    eventos:        List[str]
    materias:       List[str]


class MenuDiarioResponse(BaseModel):
    """Menú diario generado para el usuario"""
    id_menu:            int
    fecha:              str
    tipo_dia:           str
    calorias_objetivo:  int
    calorias_total:     int
    proteinas_total:    float
    grasas_total:       float
    carbohidratos_total: float
    desayuno:           List[AlimentoEnMenu]
    almuerzo:           List[AlimentoEnMenu]
    cena:               List[AlimentoEnMenu]
    snacks:             List[AlimentoEnMenu]
    contexto:           Optional[ContextoAcademicoSchema] = None
    mensaje:            Optional[str] = None
    alertas:            List[str] = []
    consumido:          bool
    fecha_generacion:   str

    class Config:
        from_attributes = True

    @field_validator('desayuno', 'almuerzo', 'cena', 'snacks', mode='before')
    @classmethod
    def parse_meal(cls, v):
        import json
        if isinstance(v, str):
            return json.loads(v) if v else []
        return v or []

    @field_validator('alertas', mode='before')
    @classmethod
    def parse_alertas(cls, v):
        import json
        if isinstance(v, str):
            return json.loads(v) if v else []
        return v or []

    @field_validator('contexto', mode='before')
    @classmethod
    def parse_contexto(cls, v):
        import json
        if isinstance(v, str):
            return json.loads(v) if v else None
        return v

    @field_validator('fecha', mode='before')
    @classmethod
    def convert_fecha_menu(cls, v):
        if isinstance(v, date):
            return v.strftime('%Y-%m-%d')
        return str(v) if v else ''

    @field_validator('fecha_generacion', mode='before')
    @classmethod
    def convert_fecha_gen(cls, v):
        if hasattr(v, 'strftime'):
            return v.strftime('%Y-%m-%dT%H:%M:%S')
        return str(v) if v else ''


class GenerarMenuRequest(BaseModel):
    """Parámetros opcionales para forzar generación de un menú"""
    fecha: Optional[str] = None   # formato "YYYY-MM-DD"; None = hoy


class MarcarConsumedoRequest(BaseModel):
    consumido: bool = True


class HistorialMenuResponse(BaseModel):
    """Resumen de menú para el historial (sin detalle de alimentos)"""
    id_menu:           int
    fecha:             str
    tipo_dia:          str
    calorias_objetivo: int
    calorias_total:    int
    consumido:         bool
    mensaje:           Optional[str] = None

    class Config:
        from_attributes = True

    @field_validator('fecha', mode='before')
    @classmethod
    def convert_fecha_h(cls, v):
        if isinstance(v, date):
            return v.strftime('%Y-%m-%d')
        return str(v) if v else ''


class EstadisticasSemana(BaseModel):
    """Estadísticas de la semana actual"""
    menus_generados:    int
    menus_consumidos:   int
    tasa_cumplimiento:  float        # 0.0 – 1.0
    promedio_calorias:  int
    historial:          List[HistorialMenuResponse]


class RegistroNutricionCreate(BaseModel):
    fecha:        str           # "YYYY-MM-DD"
    id_menu:      Optional[int] = None
    calorias:     Optional[int] = None
    proteinas:    Optional[float] = None
    grasas:       Optional[float] = None
    carbohidratos: Optional[float] = None
    agua_ml:      Optional[int] = None
    notas:        Optional[str] = None


class RegistroNutricionResponse(RegistroNutricionCreate):
    id_registro: int
    id_usuario:  int

    class Config:
        from_attributes = True
