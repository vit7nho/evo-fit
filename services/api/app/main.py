from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.types import Scope

from app import __version__
from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging
from app.core.middleware import RequestContextMiddleware
from app.modules.auth.rate_limit import RateLimiter
from app.modules.exercises.seed import IMAGES_DIR, IMAGES_URL


class _CachedStaticFiles(StaticFiles):
    """Arquivos públicos que só mudam com uma versão nova do seed: cache de 1 dia."""

    async def get_response(self, path: str, scope: Scope):
        response = await super().get_response(path, scope)
        if response.status_code == 200:
            response.headers["Cache-Control"] = "public, max-age=86400"
        return response


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(
        title=f"{settings.app_name} API",
        version=__version__,
        # Documentação interativa desligada em produção; o openapi.json exportado fica em docs/.
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
            expose_headers=["X-Request-ID"],
        )
    # Adicionado por último = mais externo: o request_id existe para todos os demais.
    app.add_middleware(RequestContextMiddleware)
    register_error_handlers(app)
    # Um limitador por instância do app (em memória; ver app/modules/auth/rate_limit.py).
    app.state.rate_limiter = RateLimiter()
    app.include_router(api_router)
    # Fotos do catálogo de exercícios (free-exercise-db, ADR-030): públicas, sem dados pessoais.
    app.mount(IMAGES_URL, _CachedStaticFiles(directory=IMAGES_DIR), name="exercise-images")
    return app


app = create_app()
