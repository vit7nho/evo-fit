from datetime import datetime

from sqlalchemy import Boolean, Index, String, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# Configuração da v1 (DATA_MODEL §6); a migração 0011 grava esta versão como ativa.
METHODOLOGY_V1 = {
    "role_weights": {"primary": 1.0, "secondary": 0.5},
    "set_kind_weights": {
        "warmup": 0.0,
        "working": 1.0,
        "drop": 0.5,
        "rest_pause": 0.33,
        "cluster": 0.33,
    },
    "drop_chain_cap": 2.0,
    "count_sets_without_reps": False,
    "bands_weekly_sets": {
        "none": [0, 0.5],
        "low": [0.5, 6],
        "mid": [6, 12],
        "high": [12, None],
    },
}


class StimulusMethodology(Base):
    """Versões da metodologia de estímulo. Uma ativa por vez; a resposta da API sempre
    diz qual versão foi usada, e mudar a configuração é criar uma versão nova."""

    __tablename__ = "stimulus_methodologies"

    version: Mapped[str] = mapped_column(String(16), primary_key=True)
    config: Mapped[dict] = mapped_column(JSONB)
    active: Mapped[bool] = mapped_column(Boolean, default=False)
    description: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    __table_args__ = (
        Index(
            "uq_stimulus_methodologies_active",
            "active",
            unique=True,
            postgresql_where=text("active"),
        ),
    )
