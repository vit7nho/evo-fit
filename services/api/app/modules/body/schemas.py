import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

Metric = Literal[
    "weight_kg",
    "body_fat_pct",
    "waist_cm",
    "hip_cm",
    "chest_cm",
    "arm_cm",
    "thigh_cm",
    "calf_cm",
]
# Limites físicos (erros de digitação), os mesmos que o app mostra.
WEIGHT_RANGE = (20.0, 350.0)
FAT_RANGE = (2.0, 75.0)
CM_RANGE = (10.0, 250.0)
Weight = Annotated[float, Field(ge=WEIGHT_RANGE[0], le=WEIGHT_RANGE[1])]
Fat = Annotated[float, Field(ge=FAT_RANGE[0], le=FAT_RANGE[1])]
Cm = Annotated[float, Field(ge=CM_RANGE[0], le=CM_RANGE[1])]
Notes = Annotated[str, StringConstraints(strip_whitespace=True, max_length=300)]


class _Values(BaseModel):
    model_config = ConfigDict(extra="forbid")

    weight_kg: Weight | None = None
    body_fat_pct: Fat | None = None
    waist_cm: Cm | None = None
    hip_cm: Cm | None = None
    chest_cm: Cm | None = None
    arm_cm: Cm | None = None
    thigh_cm: Cm | None = None
    calf_cm: Cm | None = None


class MeasurementIn(_Values):
    # Com fuso: o instante; sem fuso: o horário no fuso do perfil.
    measured_at: datetime
    notes: Notes | None = None

    @model_validator(mode="after")
    def _some_value(self) -> MeasurementIn:
        if all(getattr(self, m) is None for m in _Values.model_fields):
            raise ValueError("Informe ao menos uma medida.")
        return self


class MeasurementUpdate(_Values):
    """Parcial: só os campos enviados mudam; `null` limpa (sobrando ao menos uma)."""

    measured_at: datetime | None = None
    notes: Notes | None = None


class MeasurementOut(BaseModel):
    id: uuid.UUID
    measured_at: datetime
    # O mesmo horário no fuso do perfil, sem fuso (o que a tela mostra e edita).
    local_time: datetime
    weight_kg: float | None
    body_fat_pct: float | None
    waist_cm: float | None
    hip_cm: float | None
    chest_cm: float | None
    arm_cm: float | None
    thigh_cm: float | None
    calf_cm: float | None
    notes: str | None


class MetricInfo(BaseModel):
    metric: Metric
    label: str
    unit: Literal["kg", "%", "cm"]
    min: float
    max: float
    # Gordura corporal: o valor é uma estimativa (balança, dobras).
    estimate: bool


class TrendPoint(BaseModel):
    date: date
    value: float
    # Média dos registros dos 7 dias até este (inclusive): suaviza a variação do dia.
    average_7d: float


class TrendOut(BaseModel):
    metric: Metric
    label: str
    unit: str
    from_date: date
    to_date: date
    # Um ponto por dia com registro (o último do dia).
    points: list[TrendPoint]
    first: TrendPoint | None
    last: TrendPoint | None
    change: float | None
    min: float | None
    max: float | None
    # Ritmo por semana pela reta que melhor passa pelos pontos; nulo com menos de 3
    # pontos ou menos de 14 dias entre o primeiro e o último.
    weekly_rate: float | None
