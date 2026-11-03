import uuid
from datetime import datetime

from pydantic import BaseModel

from app.modules.training.schemas import ExerciseRef


class RecordOut(BaseModel):
    """Um recorde pessoal: o melhor valor até agora de um tipo, num exercício.

    `kind`: `max_load` (maior carga, com as repetições), `best_e1rm` (1RM estimado
    por Epley — uma estimativa, não um teste), `max_volume` (maior volume numa sessão),
    `max_reps` (peso do corpo e assistido) ou `max_duration` (por tempo).
    """

    kind: str
    value: float
    reps: int | None
    load_kg: float | None
    session_id: uuid.UUID
    achieved_at: datetime


class RecordEvent(BaseModel):
    """Recorde batido num treino: o novo valor e o anterior (só conta quando havia um)."""

    exercise_id: uuid.UUID
    kind: str
    value: float
    reps: int | None
    load_kg: float | None
    previous: float


class SessionSummary(BaseModel):
    id: uuid.UUID
    name: str
    started_at: datetime
    duration_s: int | None
    set_count: int
    volume_kg: float
    exercise_count: int
    # Os primeiros nomes, na ordem do treino, para o cartão do histórico.
    exercise_names: list[str]
    record_count: int


class SessionPage(BaseModel):
    items: list[SessionSummary]
    # Passe como `before` para a próxima página; nulo quando acabou.
    next_before: datetime | None


class HistorySet(BaseModel):
    kind: str
    reps: int | None
    load_kg: float | None
    duration_s: int | None
    to_failure: bool
    is_segment: bool


class ExerciseSession(BaseModel):
    session_id: uuid.UUID
    session_name: str
    started_at: datetime
    # Séries principais, cada uma seguida dos próprios segmentos.
    sets: list[HistorySet]
    volume_kg: float
    best_e1rm: float | None
    records: list[str]


class ExerciseHistory(BaseModel):
    exercise: ExerciseRef
    records: list[RecordOut]
    # Melhor carga para exatamente N repetições (1 a 20), só carga externa.
    rep_records: list[RecordOut]
    sessions: list[ExerciseSession]
    next_before: datetime | None


class ExerciseRecords(BaseModel):
    exercise: ExerciseRef
    records: list[RecordOut]
    last_done_at: datetime
