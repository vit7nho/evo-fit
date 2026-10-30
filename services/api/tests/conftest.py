import os
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import Connection, Engine, create_engine, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

API_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = API_DIR.parents[1]


class _TestEnv(BaseSettings):
    model_config = SettingsConfigDict(env_file=REPO_ROOT / ".env", extra="ignore")
    test_database_url: str = (
        "postgresql+psycopg://evofit:evofit_dev_only@127.0.0.1:5443/evofit_test"
    )


TEST_DATABASE_URL = _TestEnv().test_database_url

# Antes de importar o app: os testes nunca usam o banco de desenvolvimento.
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = TEST_DATABASE_URL
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")

from app.core.config import get_settings  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.main import create_app  # noqa: E402

get_settings.cache_clear()


def alembic_config(database_url: str = TEST_DATABASE_URL) -> Config:
    config = Config(str(API_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(API_DIR / "migrations"))
    config.attributes["database_url"] = database_url
    config.attributes["configure_logger"] = False
    return config


@pytest.fixture(scope="session")
def engine() -> Iterator[Engine]:
    eng = create_engine(TEST_DATABASE_URL, pool_pre_ping=True)
    try:
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
    except OperationalError:
        pytest.fail(
            "Banco de teste indisponível. Rode `docker compose up -d db-test` na raiz do repo.",
            pytrace=False,
        )
    # Esquema sempre recriado pelas migrações: os testes validam o caminho real de produção.
    command.downgrade(alembic_config(), "base")
    command.upgrade(alembic_config(), "head")
    yield eng
    eng.dispose()


@pytest.fixture
def db_connection(engine: Engine) -> Iterator[Connection]:
    with engine.connect() as connection:
        transaction = connection.begin()
        yield connection
        transaction.rollback()


@pytest.fixture
def db(db_connection: Connection) -> Iterator[Session]:
    """Sessão isolada: commits viram savepoints e tudo é revertido no fim do teste."""
    with Session(
        bind=db_connection, join_transaction_mode="create_savepoint", expire_on_commit=False
    ) as session:
        yield session


@pytest.fixture
def app() -> FastAPI:
    return create_app()


@pytest.fixture
def client(app: FastAPI, db: Session) -> Iterator[TestClient]:
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def client_without_db(app: FastAPI) -> Iterator[TestClient]:
    """Cliente para testes que não tocam no banco (erros, middleware)."""
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
