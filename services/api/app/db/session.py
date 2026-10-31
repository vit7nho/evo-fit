from collections.abc import Iterator
from functools import lru_cache

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

# Sessão do banco sempre em UTC (ADR-015): datas lidas do banco saem com "+00:00",
# iguais às criadas pela aplicação, independentemente do fuso do servidor.
# Sem timeout, um banco inalcançável (sem recusa ativa) trava a requisição indefinidamente.
CONNECT_ARGS = {"connect_timeout": 5, "options": "-c timezone=UTC"}


@lru_cache
def get_engine() -> Engine:
    return create_engine(
        get_settings().database_url,
        pool_pre_ping=True,
        connect_args=CONNECT_ARGS,
        pool_timeout=10,
    )


@lru_cache
def get_session_factory() -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(), autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """Dependência FastAPI: uma sessão por requisição; os serviços fazem o commit."""
    with get_session_factory()() as session:
        yield session
