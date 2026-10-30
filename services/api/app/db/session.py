from collections.abc import Iterator
from functools import lru_cache

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings


@lru_cache
def get_engine() -> Engine:
    return create_engine(
        get_settings().database_url,
        pool_pre_ping=True,
        # Sem timeout, um banco inalcançável (sem recusa ativa) trava a requisição indefinidamente.
        connect_args={"connect_timeout": 5},
        pool_timeout=10,
    )


@lru_cache
def get_session_factory() -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(), autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """Dependência FastAPI: uma sessão por requisição; os serviços fazem o commit."""
    with get_session_factory()() as session:
        yield session
