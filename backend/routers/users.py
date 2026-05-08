from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from sqlalchemy.sql import func
from jose import JWTError

import models, schemas, auth
from database import get_db

router = APIRouter()


# ── Helper: usuario autenticado desde el header ──────────────────

async def get_current_user(
    request: Request,
    db: Session = Depends(get_db)
) -> models.Usuario:
    auth_header = request.headers.get("Authorization")
    print(f"Header recibido: {auth_header}")
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )

    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise credentials_exception

    token = auth_header.split(" ")[1]

    try:
        payload = auth.decode_token(token)
        user_id = int(payload.get("sub"))
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
    user = db.query(models.Usuario).filter(
        models.Usuario.correo == credentials.correo
    ).first()

    if not user or not auth.verify_password(credentials.password, user.password):
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos")

    user.ultimo_login = func.now()
    db.commit()

    token = auth.create_access_token(data={"sub": user.id_usuario})
    return {"access_token": token, "token_type": "bearer"}


# ── GET /usuarios/me ─────────────────────────────────────────────

@router.get("/usuarios/me", response_model=schemas.UsuarioResponse)
async def get_me(current_user: models.Usuario = Depends(get_current_user)):
    return current_user


# ── POST /usuarios/perfil ────────────────────────────────────────

@router.post("/usuarios/perfil", response_model=schemas.PerfilResponse, status_code=201)
async def save_perfil(
    perfil_data: schemas.PerfilCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
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
async def create_materia(
    materia_data: schemas.MateriaCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
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
async def get_materias(
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    return db.query(models.Materia).filter(
        models.Materia.id_usuario == current_user.id_usuario
    ).all()


# ── POST /eventos ────────────────────────────────────────────────

@router.post("/eventos", response_model=schemas.EventoResponse, status_code=201)
async def create_evento(
    evento_data: schemas.EventoCreate,
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
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
async def get_eventos(
    db: Session = Depends(get_db),
    current_user: models.Usuario = Depends(get_current_user),
):
    return db.query(models.EventoAcademico).filter(
        models.EventoAcademico.id_usuario == current_user.id_usuario
    ).all()
