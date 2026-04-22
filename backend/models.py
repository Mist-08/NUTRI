from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey, Text, Time
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


class PerfilNutricional(Base):
    """Tabla 'perfil_nutricional' — datos físicos y objetivos"""
    __tablename__ = "perfil_nutricional"

    id_perfil             = Column(Integer, primary_key=True, index=True)
    id_usuario            = Column(Integer, ForeignKey("usuarios.id_usuario"), unique=True, nullable=False)
    edad                  = Column(Integer)
    peso                  = Column(Float)       # en kg
    altura                = Column(Float)       # en metros
    sexo                  = Column(String(20))
    nivel_actividad       = Column(String(50))  # Bajo, Moderado, Alto
    objetivo              = Column(String(50))  # Mantener, Bajar peso, Subir masa
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
