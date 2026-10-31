from fastapi import APIRouter

from app.api.v1 import health
from app.modules.auth.router import router as auth_router
from app.modules.goals.router import router as goals_router
from app.modules.users.router import router as users_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(auth_router)
api_router.include_router(users_router)
api_router.include_router(goals_router)
