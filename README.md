# Paquete de cambios — fusión de NUTRI-main en nutricampus-ai

Este paquete contiene **solo** los archivos que cambian. La estructura de
carpetas refleja exactamente la del proyecto, así que puedes extraerlo
**encima** de tu carpeta `nutricampus-ai/` y aceptar todos los reemplazos.

## Resumen de operaciones

| Operación | Cantidad | Detalle |
|-----------|----------|---------|
| Reemplazar archivo existente | 7 | 3 backend + 4 Flutter |
| Crear archivo nuevo | 19 | 14 backend + 4 Flutter + 1 README |

## Backend (`backend/`)

### Archivos a REEMPLAZAR (ya existen en tu proyecto)

| Archivo | Por qué cambia |
|---------|----------------|
| `backend/main.py` | Usa `lifespan` para correr migraciones y seeder al arrancar. Registra los 4 routers nuevos. Versión sube a 3.0.0. |
| `backend/models.py` | Suma 3 tablas (`Alimento`, `MenuDiario`, `RegistroNutricion`) y 4 campos de presupuesto en `PerfilNutricional`. Las tablas viejas no se tocan. |
| `backend/schemas.py` | Añade los DTOs de los nuevos endpoints (≈ 200 líneas al final). |

### Archivos NUEVOS (no existen en tu proyecto)

Routers:
- `backend/routers/recommendations.py` — menú del día generado por la IA
- `backend/routers/menus.py` — historial / consumido / eliminar
- `backend/routers/budget.py` — gestión de presupuesto
- `backend/routers/chatbot.py` — asistente conversacional

Services (carpeta nueva):
- `backend/services/__init__.py`
- `backend/services/recommendation_engine.py` — motor de IA
- `backend/services/menu_service.py`
- `backend/services/budget_service.py`
- `backend/services/chatbot_service.py`
- `backend/services/chatbot_intents.py`
- `backend/services/chatbot_context_builder.py`
- `backend/services/seeder.py` — siembra el catálogo de alimentos
- `backend/services/migrations.py` — agrega columnas faltantes a tablas existentes (no rompe nada)

Data (carpeta nueva):
- `backend/data/__init__.py`
- `backend/data/foods_db.py` — catálogo inicial de alimentos

### Archivos que NO se incluyen porque NO cambian de verdad

`auth.py`, `database.py`, `requirements.txt`, `routers/__init__.py`,
`routers/users.py`. (En NUTRI-main solo diferían en finales de línea CRLF/LF,
sin cambios reales de contenido.) Déjalos como están.

## Frontend (`nutricampus_ai/lib/`)

### Archivos a REEMPLAZAR (ya existen en tu proyecto)

| Archivo | Por qué cambia |
|---------|----------------|
| `lib/main.dart` | Importa las 4 pantallas nuevas y registra sus rutas (`/recomendacion`, `/estadisticas_nutricion`, `/chatbot`, `/presupuesto`). |
| `lib/api_service.dart` | Añade los métodos de los nuevos endpoints + un `catch` para errores de red en Flutter Web. |
| `lib/home_screen.dart` | Añade 3 tarjetas de navegación (Recomendación, Asistente, Presupuesto). También moderniza `withOpacity()` → `withValues(alpha:)`. |
| `lib/nutritional_profile_screen.dart` | Refactor: se quitaron la clase `Macros`, `_calcularMacros()` y `_MacrosCard` porque la lógica se movió al backend (`services/recommendation_engine.py`) y la visualización vive ahora en `recommendation_screen.dart` con macros reales del menú generado, no teóricos. |

### Archivos NUEVOS (no existen en tu proyecto)

- `lib/recommendation_screen.dart` — menú del día con IA
- `lib/chatbot_screen.dart` — asistente conversacional
- `lib/budget_screen.dart` — gestión de presupuesto
- `lib/nutrition_stats_screen.dart` — estadísticas de los últimos 7 días

### Archivos que NO se incluyen porque NO cambian (o cambian solo cosméticamente)

- `lib/login_screen.dart`, `lib/register_screen.dart`: idénticos en ambas
  ramas.
- `lib/horario_screen.dart`, `lib/materias_screen.dart`: solo modernizan
  `withOpacity()` → `withValues(alpha:)`. Tu versión vieja sigue
  compilando perfectamente con Flutter actual (solo lanza un *warning* de
  deprecación). Si te molesta el warning, copia también estos dos archivos
  desde NUTRI-main, pero no es obligatorio.

## Pasos para aplicar los cambios

1. Hacer **backup** del proyecto actual (por las dudas).
2. Extraer este zip encima de la carpeta `nutricampus-ai/` (acepta sobrescribir).
3. Backend:
   ```bash
   cd backend
   # No hay dependencias nuevas en requirements.txt, no hace falta pip install
   uvicorn main:app --reload
   ```
   En el primer arranque verás logs de:
   - `apply_missing_columns`: añade las columnas de presupuesto a `perfil_nutricional`
   - `seed_alimentos`: pobla la tabla `alimentos`
4. Frontend:
   ```bash
   cd nutricampus_ai
   flutter pub get   # sin cambios en pubspec, pero por si acaso
   flutter run
   ```

## Sobre la base de datos

`services/migrations.py` corre `ALTER TABLE` seguros: agrega columnas que
falten, nunca borra. Tu BD existente queda intacta — solo se le suman:

- 4 columnas nuevas en `perfil_nutricional` (presupuesto)
- 3 tablas nuevas: `alimentos`, `menus_diarios`, `registros_nutricion`

El catálogo de alimentos se siembra automáticamente desde
`backend/data/foods_db.py`.
