from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base


class User(Base):
    """Tabla principal de usuarios — datos de cuenta"""
    __tablename__ = "users"

    id            = Column(Integer, primary_key=True, index=True)
    name          = Column(String, nullable=False)
    email         = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    created_at    = Column(DateTime(timezone=True), server_default=func.now())

    # Relación 1-a-1 con el perfil nutricional
    profile = relationship("NutritionalProfile", back_populates="user", uselist=False)


class NutritionalProfile(Base):
    """Perfil nutricional — se llena después del registro"""
    __tablename__ = "nutritional_profiles"

    id             = Column(Integer, primary_key=True, index=True)
    user_id        = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    age            = Column(Integer)
    weight_kg      = Column(Float)
    height_cm      = Column(Float)
    gender         = Column(String)
    goal           = Column(String)   # 'Perder peso', 'Ganar músculo', etc.
    activity_level = Column(String)   # 'sedentary', 'light', 'moderate', etc.
    updated_at     = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", back_populates="profile")
