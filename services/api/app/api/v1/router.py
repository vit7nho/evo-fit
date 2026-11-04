from fastapi import APIRouter

from app.api.v1 import health
from app.modules.activities.router import router as activities_router
from app.modules.auth.router import router as auth_router
from app.modules.exercises.router import router as exercises_router
from app.modules.goals.router import router as goals_router
from app.modules.history.router import router as history_router
from app.modules.sessions.router import router as sessions_router
from app.modules.training.router import router as training_router
from app.modules.users.router import router as users_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(auth_router)
api_router.include_router(users_router)
api_router.include_router(goals_router)
api_router.include_router(exercises_router)
api_router.include_router(training_router)
api_router.include_router(sessions_router)
api_router.include_router(history_router)
api_router.include_router(activities_router)
