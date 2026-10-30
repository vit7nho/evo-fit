import logging
from typing import Literal

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app import __version__
from app.core.config import Settings, get_settings
from app.db.session import get_db

logger = logging.getLogger(__name__)
router = APIRouter(tags=["sistema"])


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    database: Literal["ok", "unavailable"]
    version: str
    environment: str


@router.get(
    "/health",
    response_model=HealthResponse,
    responses={503: {"model": HealthResponse, "description": "Banco indisponível"}},
    summary="Verifica se a API e o banco estão respondendo",
)
def health(
    db: Session = Depends(get_db), settings: Settings = Depends(get_settings)
) -> JSONResponse:
    try:
        db.execute(text("SELECT 1"))
        database_ok = True
    except SQLAlchemyError:
        logger.warning("health_database_unavailable")
        database_ok = False

    body = HealthResponse(
        status="ok" if database_ok else "degraded",
        database="ok" if database_ok else "unavailable",
        version=__version__,
        environment=settings.app_env.value,
    )
    return JSONResponse(body.model_dump(), status_code=200 if database_ok else 503)
