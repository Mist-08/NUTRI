from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from sqlalchemy.sql import func
from jose import JWTError

import models, schemas, auth
from database import get_db

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


# ── Helper: usuario autenticado desde token ──────────────────────

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> models.Usuario:
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

    user = db.query(models.Usuario).filter(
        models.Usuario.id_usuario == user_id
    ).first()
    if user is None:
        raise credentials_exception
    return user


# ── POST /auth/register ──────────────────────────────────────────

@router.post("/auth/register", response_model=schemas.UsuarioResponse, status_code=201)
def register(user_data: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    """Crea una cuenta nueva en la tabla 'usuarios'"""
    existing = db.query(models.Usuario).filter(
        models.Usuario.correo == user_data.correo
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Este correo ya está registrado")

    nuevo = models.Usuario(
        nombre=user_data.nombre,
        correo=user_data.correo,
        password=auth.hash_password(user_data.password),
        activo=True,
    )
    db.add(nuevo)
    db.commit()
    db.refresh(nuevo)
    return nuevo


# ── POST /auth/login ─────────────────────────────────────────────

@router.post("/auth/login", response_model=schemas.TokenResponse)
def login(credentials: schemas.LoginRequest, db: Session = Depends(get_db)):
    """Valida correo + contraseña y devuelve un token JWT"""
    user = db.query(models.Usuario).filter(
        models.Usuario.correo == credentials.correo
    ).first()

    if not user or not auth.verify_password(credentials.password, user.password):
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos")

    # Actualizar ultimo_login
    user.ultimo_login = func.now()
    db.commit()

    token = auth.create_access_token(data={"sub": user.id_usuario})
    return {"access_token": token, "token_type": "bearer"}


# ── GET /usuarios/me ─────────────────────────────────────────────

@router.get("/usuarios/me", response_model=schemas.UsuarioResponse)
def get_me(current_user: models.Usuario = Depends(get_current_user)):
    """Devuelve los datos del usuario con sesión activa"""
    return current_user


# ── POST /usuarios/perfil ────────────────────────────────────────

@router.post("/usuarios/perfil", response_model=schemas.PerfilResponse, status_code=201)
def save_perfil(
    perfil_data: schemas.PerfilCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Guarda o actualiza el perfil nutricional del usuario autenticado"""
    perfil = db.query(models.PerfilNutricional).filter(
        models.PerfilNutricional.id_usuario == current_user.id_usuario
    ).first()

    if perfil:
        for key, value in perfil_data.model_dump().items():
            setattr(perfil, key, value)
    else:
        perfil = models.PerfilNutricional(
            id_usuario=current_user.id_usuario,
            **perfil_data.model_dump()
        )
        db.add(perfil)

    db.commit()
    db.refresh(perfil)
    return perfil


# ── POST /materias ───────────────────────────────────────────────

@router.post("/materias", response_model=schemas.MateriaResponse, status_code=201)
def create_materia(
    materia_data: schemas.MateriaCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Registra una nueva materia del horario semanal"""
    materia = models.Materia(
        id_usuario=current_user.id_usuario,
        **materia_data.model_dump()
    )
    db.add(materia)
    db.commit()
    db.refresh(materia)
    return materia


# ── GET /materias ────────────────────────────────────────────────

@router.get("/materias", response_model=list[schemas.MateriaResponse])
def get_materias(
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Devuelve todas las materias del usuario autenticado"""
    return db.query(models.Materia).filter(
        models.Materia.id_usuario == current_user.id_usuario
    ).all()


# ── POST /eventos ────────────────────────────────────────────────

@router.post("/eventos", response_model=schemas.EventoResponse, status_code=201)
def create_evento(
    evento_data: schemas.EventoCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Registra un nuevo evento académico (examen o entrega)"""
    evento = models.EventoAcademico(
        id_usuario=current_user.id_usuario,
        **evento_data.model_dump()
    )
    db.add(evento)
    db.commit()
    db.refresh(evento)
    return evento


# ── GET /eventos ─────────────────────────────────────────────────

@router.get("/eventos", response_model=list[schemas.EventoResponse])
def get_eventos(
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    """Devuelve todos los eventos del usuario autenticado"""
    return db.query(models.EventoAcademico).filter(
        models.EventoAcademico.id_usuario == current_user.id_usuario
    ).all()
