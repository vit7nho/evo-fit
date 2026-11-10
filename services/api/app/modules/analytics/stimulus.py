"""Estímulo muscular: séries ponderadas por músculo (metodologia v1, DATA_MODEL §6).

Função pura: recebe as séries já filtradas (do dono, de treinos concluídos e não
excluídos, no período), os músculos de cada exercício e a configuração da versão ativa.
As faixas são referências gerais de volume registrado, não prescrições nem diagnóstico.
"""

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class SetRow:
    id: uuid.UUID
    day: date
    exercise_id: uuid.UUID
    kind: str
    parent_set_id: uuid.UUID | None = None
    reps: int | None = None
    duration_s: int | None = None
    load_kg: float | None = None
    # external | bodyweight | assisted | none (do exercício)
    load_type: str = "external"


@dataclass(frozen=True)
class MuscleRef:
    muscle_id: str
    role: str  # primary | secondary


@dataclass
class MuscleStimulus:
    muscle_id: str
    weighted_sets: float = 0.0
    weighted_sets_per_week: float = 0.0
    band: str = "none"
    frequency: int = 0
    volume_load_kg: float = 0.0
    # exercício -> séries ponderadas que ele deu a este músculo
    exercises: dict[uuid.UUID, float] = field(default_factory=dict)


def band_for(per_week: float, bands: dict[str, list[float | None]]) -> str:
    """Faixa pelo intervalo [mínimo, máximo) da configuração; o último não tem teto.
    Um intervalo [x, x] vale só para x exato e tem prioridade (a v2 usa `none: [0, 0]`:
    qualquer estímulo acima de zero já entra na faixa seguinte). Não depende da ordem
    das chaves, que o JSONB não guarda."""
    points = {name: low for name, (low, high) in bands.items() if high is not None and low == high}
    for name, value in points.items():
        if per_week == value:
            return name
    for name, (low, high) in bands.items():
        if name in points:
            continue
        if per_week >= (low or 0) and (high is None or per_week < high):
            return name
    return "none"


def set_values(sets: list[SetRow], config: dict) -> dict[uuid.UUID, float]:
    """Valor de cada série: o peso do tipo, com a soma de uma cadeia (série principal +
    segmentos de drop/rest-pause) limitada pelo teto. Aquecimento vale 0; sem
    repetições nem tempo, a série só conta se a configuração mandar."""
    weights: dict[str, float] = config["set_kind_weights"]
    cap: float = config["drop_chain_cap"]
    count_empty: bool = config["count_sets_without_reps"]

    def counts(s: SetRow) -> bool:
        return count_empty or bool(s.reps) or bool(s.duration_s)

    values: dict[uuid.UUID, float] = {}
    chains: dict[uuid.UUID, list[SetRow]] = defaultdict(list)
    for s in sets:
        chains[s.parent_set_id or s.id].append(s)
    for root, chain in chains.items():
        # A principal primeiro, depois os segmentos na ordem em que vieram.
        chain.sort(key=lambda s: s.id != root)
        used = 0.0
        for s in chain:
            value = weights.get(s.kind, 0.0) if counts(s) else 0.0
            value = max(0.0, min(value, cap - used))
            used += value
            values[s.id] = value
    return values


def muscle_stimulus(
    sets: list[SetRow],
    muscles: dict[uuid.UUID, list[MuscleRef]],
    all_muscles: list[str],
    config: dict,
    days: int,
) -> list[MuscleStimulus]:
    """Uma linha por músculo do catálogo (zerada se não treinado), com as séries
    ponderadas por semana — comparáveis entre períodos de tamanhos diferentes."""
    role_weights: dict[str, float] = config["role_weights"]
    values = set_values(sets, config)
    result = {m: MuscleStimulus(m) for m in all_muscles}
    trained_days: dict[str, set[date]] = defaultdict(set)

    for s in sets:
        value = values[s.id]
        volume = (
            (s.load_kg or 0) * (s.reps or 0)
            if s.load_type == "external" and s.kind != "warmup"
            else 0.0
        )
        for ref in muscles.get(s.exercise_id, []):
            if ref.muscle_id not in result:
                continue
            weight = role_weights.get(ref.role, 0.0)
            row = result[ref.muscle_id]
            contribution = value * weight
            if contribution > 0:
                row.weighted_sets += contribution
                row.exercises[s.exercise_id] = row.exercises.get(s.exercise_id, 0) + contribution
                trained_days[ref.muscle_id].add(s.day)
            # Volume também ponderado pelo papel: o secundário recebe metade.
            row.volume_load_kg += volume * weight

    weeks = days / 7
    for muscle_id, row in result.items():
        row.weighted_sets = round(row.weighted_sets, 2)
        per_week = row.weighted_sets / weeks if weeks else 0.0
        row.weighted_sets_per_week = round(per_week, 2)
        # A faixa usa o valor sem arredondar: um estímulo pequeno num período longo
        # (0,17 série em 366 dias) não pode virar zero e cair na faixa "nenhuma".
        row.band = band_for(per_week, config["bands_weekly_sets"])
        row.frequency = len(trained_days[muscle_id])
        row.volume_load_kg = round(row.volume_load_kg, 2)
        row.exercises = {k: round(v, 2) for k, v in row.exercises.items()}
    return list(result.values())
