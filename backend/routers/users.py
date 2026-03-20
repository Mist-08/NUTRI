from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import JWTError

import models, schemas, auth
from database import get_db

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


# ── Helper: obtener usuario autenticado desde el token ──────────

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> models.User:
    """Decodifica el JWT y devuelve el usuario de la BD"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = auth.decode_token(token)
        user_id: int = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user is None:
        raise credentials_exception
    return user


# ── POST /auth/register ─────────────────────────────────────────

@router.post("/auth/register", response_model=schemas.UserResponse, status_code=201)
def register(user_data: schemas.UserCreate, db: Session = Depends(get_db)):
    """Crea una cuenta nueva. Hashea la contraseña con bcrypt."""

    # Verificar que el correo no exista ya
    existing = db.query(models.User).filter(models.User.email == user_data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Este correo ya está registrado")

    new_user = models.User(
        name=user_data.name,
        email=user_data.email,
        hashed_password=auth.hash_password(user_data.password),
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user


# ── POST /auth/login ────────────────────────────────────────────

@router.post("/auth/login", response_model=schemas.TokenResponse)
def login(credentials: schemas.LoginRequest, db: Session = Depends(get_db)):
    """Valida email + contraseña y devuelve un token JWT."""

    user = db.query(models.User).filter(models.User.email == credentials.email).first()

    if not user or not auth.verify_password(credentials.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos")

    token = auth.create_access_token(data={"sub": user.id})
    return {"access_token": token, "token_type": "bearer"}


# ── POST /users/profile ─────────────────────────────────────────

@router.post("/users/profile", response_model=schemas.ProfileResponse, status_code=201)
def save_profile(
    profile_data: schemas.ProfileCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Guarda o actualiza el perfil nutricional del usuario autenticado."""

    profile = db.query(models.NutritionalProfile).filter(
        models.NutritionalProfile.user_id == current_user.id
    ).first()

    if profile:
        # Actualizar perfil existente
        for key, value in profile_data.model_dump().items():
            setattr(profile, key, value)
    else:
        # Crear perfil nuevo
        profile = models.NutritionalProfile(
            user_id=current_user.id,
            **profile_data.model_dump()
        )
        db.add(profile)

    db.commit()
    db.refresh(profile)
    return profile


# ── GET /users/me ───────────────────────────────────────────────

@router.get("/users/me", response_model=schemas.UserResponse)
def get_me(current_user: models.User = Depends(get_current_user)):
    """Devuelve los datos del usuario autenticado."""
    return current_user
