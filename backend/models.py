from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey, Text, Time, Date
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base


class Usuario(Base):
    """Tabla 'usuarios' — datos de cuenta"""
    __tablename__ = "usuarios"

    id_usuario        = Column(Integer, primary_key=True, index=True)
    nombre            = Column(String(100), nullable=False)
    correo            = Column(String(150), unique=True, index=True, nullable=False)
    password          = Column(Text, nullable=False)  # hash bcrypt
    activo            = Column(Boolean, default=True)
    ultimo_login      = Column(DateTime(timezone=True), nullable=True)
    fecha_registro    = Column(DateTime(timezone=True), server_default=func.now())

    # Relaciones
    perfil            = relationship("PerfilNutricional", back_populates="usuario", uselist=False)
    eventos           = relationship("EventoAcademico", back_populates="usuario")
    materias          = relationship("Materia", back_populates="usuario")
    menus             = relationship("MenuDiario", back_populates="usuario")
    registros         = relationship("RegistroNutricion", back_populates="usuario")


class PerfilNutricional(Base):
    """Tabla 'perfil_nutricional' — datos físicos y objetivos"""
    __tablename__ = "perfil_nutricional"

    id_perfil             = Column(Integer, primary_key=True, index=True)
    id_usuario            = Column(Integer, ForeignKey("usuarios.id_usuario"), unique=True, nullable=False)
    edad                  = Column(Integer)
    fecha_nacimiento      = Column(Date, nullable=True)  # nullable para perfiles legacy
    peso                  = Column(Float)       # en kg
    altura                = Column(Float)       # en cm (el frontend usa cm; la fórmula IMC divide entre 100)
    sexo                  = Column(String(20))
    nivel_actividad       = Column(String(50))  # Bajo, Moderado, Alto, Muy alto
    objetivo              = Column(String(50))  # Mantener, Bajar peso, Subir masa, Mejorar rendimiento
    alergias              = Column(Text, nullable=True)
    dieta                 = Column(String(50), nullable=True)
    calorias_diarias      = Column(Integer, nullable=True)
    condiciones_medicas   = Column(Text, nullable=True)
    fecha_actualizacion   = Column(DateTime(timezone=True), onupdate=func.now())

    usuario = relationship("Usuario", back_populates="perfil")


class EventoAcademico(Base):
    """Tabla 'eventos_academicos' — exámenes y entregas"""
    __tablename__ = "eventos_academicos"

    id_evento     = Column(Integer, primary_key=True, index=True)
    id_usuario    = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    tipo_evento   = Column(String(20), nullable=False)  # Examen, Clase, Entrega
    fecha         = Column(DateTime, nullable=False)
    hora_inicio   = Column(Time, nullable=False)
    hora_fin      = Column(Time, nullable=True)
    descripcion   = Column(String(255), nullable=True)

    usuario = relationship("Usuario", back_populates="eventos")


class Materia(Base):
    """Tabla 'materias' — horario semanal fijo"""
    __tablename__ = "materias"

    id_materia    = Column(Integer, primary_key=True, index=True)
    id_usuario    = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    nombre        = Column(String(100), nullable=False)
    aula          = Column(String(50), nullable=True)
    profesor      = Column(String(100), nullable=True)
    color         = Column(String(7), default='#4CAF50')
    lunes         = Column(Boolean, default=False)
    martes        = Column(Boolean, default=False)
    miercoles     = Column(Boolean, default=False)
    jueves        = Column(Boolean, default=False)
    viernes       = Column(Boolean, default=False)
    hora_inicio   = Column(Time, nullable=False)
    hora_fin      = Column(Time, nullable=False)

    usuario = relationship("Usuario", back_populates="materias")


# ── Nutrición ─────────────────────────────────────────────────────

class Alimento(Base):
    """Tabla 'alimentos' — catálogo de alimentos para recomendaciones"""
    __tablename__ = "alimentos"

    id_alimento       = Column(Integer, primary_key=True, index=True)
    nombre            = Column(String(200), nullable=False)
    tipo_comida       = Column(String(30), nullable=False)   # Desayuno, Almuerzo, Cena, Snack
    calorias          = Column(Integer, nullable=False)
    proteinas         = Column(Float, nullable=False)
    grasas            = Column(Float, nullable=False)
    carbohidratos     = Column(Float, nullable=False)
    descripcion       = Column(Text, nullable=True)
    porcion           = Column(String(100), nullable=False)
    beneficios        = Column(Text, nullable=True)
    advertencias      = Column(Text, nullable=True)

    # Restricciones dietéticas
    apto_vegetariano  = Column(Boolean, default=True)
    apto_vegano       = Column(Boolean, default=False)
    sin_gluten        = Column(Boolean, default=True)
    sin_lactosa       = Column(Boolean, default=True)
    sin_huevo         = Column(Boolean, default=True)
    sin_mariscos      = Column(Boolean, default=True)
    sin_frutos_secos  = Column(Boolean, default=True)
    sin_soya          = Column(Boolean, default=True)
    sin_pescado       = Column(Boolean, default=True)
    sin_mani          = Column(Boolean, default=True)
    sin_mostaza       = Column(Boolean, default=True)
    sin_sesamo        = Column(Boolean, default=True)

    # Etiquetas de contexto
    bueno_examen      = Column(Boolean, default=False)   # óptimo para días de examen
    alta_proteina     = Column(Boolean, default=False)   # alto en proteína
    alto_rendimiento  = Column(Boolean, default=False)   # alta carga académica
    ligero            = Column(Boolean, default=False)   # bajo en calorías / digestión fácil


class MenuDiario(Base):
    """Tabla 'menus_diarios' — menús generados por el motor de recomendación"""
    __tablename__ = "menus_diarios"

    id_menu           = Column(Integer, primary_key=True, index=True)
    id_usuario        = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    fecha             = Column(Date, nullable=False, index=True)
    tipo_dia          = Column(String(30), nullable=False)   # normal, examen, entrega, alta_carga, descanso
    calorias_objetivo = Column(Integer, nullable=False)
    calorias_total    = Column(Integer, nullable=True)
    proteinas_total   = Column(Float, nullable=True)
    grasas_total      = Column(Float, nullable=True)
    carbohidratos_total = Column(Float, nullable=True)

    # Comidas almacenadas como JSON string
    desayuno          = Column(Text, nullable=True)
    almuerzo          = Column(Text, nullable=True)
    cena              = Column(Text, nullable=True)
    snacks            = Column(Text, nullable=True)

    # Contexto académico serializado como JSON
    contexto          = Column(Text, nullable=True)

    mensaje           = Column(Text, nullable=True)
    alertas           = Column(Text, nullable=True)         # JSON list of strings
    consumido         = Column(Boolean, default=False)
    fecha_generacion  = Column(DateTime(timezone=True), server_default=func.now())

    usuario = relationship("Usuario", back_populates="menus")


class RegistroNutricion(Base):
    """Tabla 'registros_nutricion' — seguimiento diario de nutrición"""
    __tablename__ = "registros_nutricion"

    id_registro       = Column(Integer, primary_key=True, index=True)
    id_usuario        = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    fecha             = Column(Date, nullable=False, index=True)
    id_menu           = Column(Integer, ForeignKey("menus_diarios.id_menu"), nullable=True)
    calorias          = Column(Integer, nullable=True)
    proteinas         = Column(Float, nullable=True)
    grasas            = Column(Float, nullable=True)
    carbohidratos     = Column(Float, nullable=True)
    agua_ml           = Column(Integer, nullable=True)
    notas             = Column(Text, nullable=True)
    fecha_registro    = Column(DateTime(timezone=True), server_default=func.now())

    usuario = relationship("Usuario", back_populates="registros")
