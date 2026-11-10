"""Indicadores calculados a partir dos registros (funções puras, ARCHITECTURE §5).

Nada aqui lê o banco: o serviço monta as `Entry` (uma por treino ou atividade, com o
dia no fuso da pessoa) e estas funções fazem as contas. Semanas começam na segunda.
"""

from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, timedelta

STRENGTH = "strength"


@dataclass(frozen=True)
class Entry:
    day: date
    modality: str
    duration_s: int
    distance_m: int | None = None
    # Só na musculação: séries válidas (sem aquecimento) e volume (carga externa vezes reps).
    sets: int = 0
    volume_kg: float = 0.0


def week_start(day: date) -> date:
    return day - timedelta(days=day.weekday())


def weeks_between(start: date, end: date) -> list[date]:
    """Segundas das semanas que tocam o período (as das pontas podem ser parciais)."""
    weeks, current = [], week_start(start)
    while current <= end:
        weeks.append(current)
        current += timedelta(days=7)
    return weeks


def _round(value: float) -> float:
    return round(value, 2)


# --- frequência e consistência ---


def weekly(entries: Iterable[Entry], start: date, end: date) -> list[dict]:
    by_week: dict[date, list[Entry]] = defaultdict(list)
    for entry in entries:
        by_week[week_start(entry.day)].append(entry)
    return [
        {
            "week_start": week,
            "active_days": len({e.day for e in by_week[week]}),
            "sessions": len(by_week[week]),
            "duration_s": sum(e.duration_s for e in by_week[week]),
        }
        for week in weeks_between(start, end)
    ]


def consistency(weeks: list[dict], weekly_target: int | None, today: date) -> dict[str, int | None]:
    """Semanas com atividade, semanas que bateram a meta de dias (do perfil) e a
    sequência atual de semanas ativas. A semana em curso só conta para a sequência se
    já tiver atividade: ainda dá tempo de treinar."""
    active = [w for w in weeks if w["active_days"] > 0]
    streak = 0
    for week in reversed(weeks):
        if week["active_days"] > 0:
            streak += 1
        elif week["week_start"] == week_start(today):
            continue
        else:
            break
    return {
        "weeks": len(weeks),
        "active_weeks": len(active),
        "weeks_on_target": (
            sum(1 for w in weeks if w["active_days"] >= weekly_target) if weekly_target else None
        ),
        "current_streak_weeks": streak,
    }


def by_modality(entries: Iterable[Entry]) -> list[dict]:
    groups: dict[str, list[Entry]] = defaultdict(list)
    for entry in entries:
        groups[entry.modality].append(entry)
    result = []
    for modality, items in groups.items():
        distances = [e.distance_m for e in items if e.distance_m is not None]
        strength = modality == STRENGTH
        result.append(
            {
                "modality": modality,
                "sessions": len(items),
                "duration_s": sum(e.duration_s for e in items),
                "distance_m": sum(distances) if distances else None,
                "sets": sum(e.sets for e in items) if strength else None,
                "volume_kg": _round(sum(e.volume_kg for e in items)) if strength else None,
            }
        )
    # Mais frequente primeiro; empate pelo nome, para a ordem ser estável.
    return sorted(result, key=lambda m: (-m["sessions"], m["modality"]))


# --- resistência ---


def rhythm(modality: str, distance_m: int, duration_s: int) -> dict[str, float | int | None]:
    """Pace e velocidade médios, ponderados: soma do tempo ÷ soma da distância (só das
    atividades com distância). Mesma convenção da API de atividades (3.2)."""
    if distance_m <= 0 or duration_s <= 0:
        return {"pace_s_per_km": None, "speed_kmh": None, "pace_s_per_100m": None}
    if modality == "swim":
        return {
            "pace_s_per_km": None,
            "speed_kmh": None,
            "pace_s_per_100m": round(duration_s / distance_m * 100),
        }
    return {
        "pace_s_per_km": round(duration_s / distance_m * 1000),
        "speed_kmh": round(distance_m / duration_s * 3.6, 1),
        "pace_s_per_100m": None,
    }


def endurance_weeks(entries: Iterable[Entry], modality: str, start: date, end: date) -> list[dict]:
    by_week: dict[date, list[Entry]] = defaultdict(list)
    for entry in entries:
        by_week[week_start(entry.day)].append(entry)
    weeks = []
    for week in weeks_between(start, end):
        items = by_week[week]
        measured = [e for e in items if e.distance_m]
        distance = sum(e.distance_m or 0 for e in measured)
        weeks.append(
            {
                "week_start": week,
                "sessions": len(items),
                "duration_s": sum(e.duration_s for e in items),
                "distance_m": distance,
                **rhythm(modality, distance, sum(e.duration_s for e in measured)),
            }
        )
    return weeks


def complete_weeks(weeks: list[dict], start: date, end: date) -> list[dict]:
    """Só as semanas inteiras dentro do período. A semana em andamento (e uma ponta
    cortada pelo período) puxaria a tendência para baixo sem a pessoa ter treinado
    menos: ainda faltam dias."""
    return [
        w for w in weeks if w["week_start"] >= start and w["week_start"] + timedelta(days=6) <= end
    ]


def trend(values: list[float], min_points: int = 3) -> dict[str, float | str | None]:
    """Reta de mínimos quadrados pelos valores semanais. `flat` quando a inclinação é
    menor que 5% da média por semana; sem dados suficientes, tudo nulo (não inventa)."""
    if len(values) < min_points or not any(values):
        return {"direction": None, "per_week": None}
    n = len(values)
    mean_x = (n - 1) / 2
    mean_y = sum(values) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in enumerate(values))
    den = sum((x - mean_x) ** 2 for x in range(n))
    slope = num / den
    direction = "up" if slope > 0 else "down"
    if abs(slope) < 0.05 * mean_y:
        direction = "flat"
    return {"direction": direction, "per_week": _round(slope)}


# --- comparação de períodos ---


@dataclass(frozen=True)
class Metric:
    code: str
    label: str
    # True quando um valor maior é melhor (pace: menor é melhor).
    higher_is_better: bool
    needs_modality: bool = False


METRICS = {
    m.code: m
    for m in (
        Metric("sessions", "Treinos e atividades", True),
        Metric("active_days", "Dias ativos", True),
        Metric("duration_s", "Tempo total", True),
        Metric("strength_sets", "Séries de musculação", True),
        Metric("strength_volume_kg", "Volume de musculação", True),
        Metric("distance_m", "Distância", True, needs_modality=True),
        Metric("pace_s_per_km", "Pace médio", False, needs_modality=True),
    )
}


def metric_value(code: str, entries: list[Entry], modality: str | None = None) -> float | None:
    """O valor de um período. Nulo quando não há como calcular (pace sem distância),
    para nunca comparar com um zero inventado."""
    if modality is not None:
        entries = [e for e in entries if e.modality == modality]
    match code:
        case "sessions":
            return len(entries)
        case "active_days":
            return len({e.day for e in entries})
        case "duration_s":
            return sum(e.duration_s for e in entries)
        case "strength_sets":
            return sum(e.sets for e in entries if e.modality == STRENGTH)
        case "strength_volume_kg":
            return _round(sum(e.volume_kg for e in entries if e.modality == STRENGTH))
        case "distance_m":
            return sum(e.distance_m or 0 for e in entries)
        case "pace_s_per_km":
            measured = [e for e in entries if e.distance_m]
            distance = sum(e.distance_m or 0 for e in measured)
            return rhythm("run", distance, sum(e.duration_s for e in measured))["pace_s_per_km"]
    raise ValueError(code)


def compare(code: str, base: float | None, other: float | None) -> dict:
    """`other` comparado com `base`. O percentual só sai com base válida (> 0): de 0
    para 3 treinos não é “+∞%”, e sem valor não há comparação."""
    metric = METRICS[code]
    if base is None or other is None:
        return {"difference": None, "percent": None, "better": None}
    difference = _round(other - base)
    percent = _round((other - base) / base * 100) if base > 0 else None
    if difference == 0:
        better = "same"
    elif (difference > 0) == metric.higher_is_better:
        better = "b"
    else:
        better = "a"
    return {"difference": difference, "percent": percent, "better": better}
