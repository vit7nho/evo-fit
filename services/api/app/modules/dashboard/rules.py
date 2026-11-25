"""Regras do painel do Início (3.8), sem banco: o que aparece, em que ordem, e o
progresso das metas que dá para medir com os registros.

O serviço junta os fatos (registros, estímulo, plano ativo) e estas funções decidem.
"""

from dataclasses import dataclass
from datetime import date

from app.modules.analytics.metrics import STRENGTH

ENDURANCE = ("run", "walk", "cycle", "swim")

# A modalidade que o objetivo principal põe em primeiro lugar.
OBJECTIVE_MODALITY = {"gain_muscle": STRENGTH, "run": "run", "walk_habit": "walk"}
# Objetivos em que o plano ativo (caminhada, 5 km, 10 km) é o primeiro cartão.
PLAN_FIRST = {"run", "walk_habit"}


def focus_order(
    objective: str | None,
    preferred: list[str],
    recorded: dict[str, int],
    has_plan: bool,
) -> list[str]:
    """Cartões de foco, em ordem: `strength`, `body`, `endurance:<modalidade>` e `plan`.

    Entram as modalidades preferidas do perfil (na ordem dele) e as que tiveram
    registro nos últimos 30 dias (as mais frequentes primeiro): modalidade que a
    pessoa não usa não aparece. O objetivo principal sobe a modalidade dele para o
    topo; musculação traz junto o Meu Corpo; o plano ativo abre o painel de quem quer
    correr ou caminhar e fecha o dos demais.
    """
    known = (STRENGTH, *ENDURANCE)
    modalities = [m for m in preferred if m in known]
    for modality, _ in sorted(recorded.items(), key=lambda kv: (-kv[1], kv[0])):
        if modality in known and modality not in modalities:
            modalities.append(modality)
    if (main := OBJECTIVE_MODALITY.get(objective or "")) is not None:
        modalities = [main, *(m for m in modalities if m != main)]

    cards: list[str] = []
    for modality in modalities:
        cards.extend(["strength", "body"] if modality == STRENGTH else [f"endurance:{modality}"])
    if has_plan and objective in PLAN_FIRST:
        cards.insert(0, "plan")
    elif has_plan:
        cards.append("plan")
    return cards


@dataclass(frozen=True)
class Progress:
    current: float | None
    target: float
    unit: str  # kg | km | s | sets_per_week | sessions
    basis: str
    lower_is_better: bool = False
    # Metas de peso (5.3): o peso de quando a meta começou, para medir o caminho
    # percorrido até o alvo (e não a razão entre dois pesos).
    start: float | None = None
    # Manutenção de peso: a meta é ficar a até `tolerance` do alvo.
    tolerance: float | None = None

    @property
    def achieved(self) -> bool:
        if self.current is None:
            return False
        if self.tolerance is not None:
            return abs(self.current - self.target) <= self.tolerance + 1e-9
        if self.lower_is_better:
            return self.current <= self.target
        return self.current >= self.target

    @property
    def ratio(self) -> float | None:
        """De 0 a 1 (atingido = 1). Sem valor medido, nulo: não vira zero."""
        if self.current is None:
            return None
        if self.tolerance is not None:
            return 1.0 if self.achieved else 0.0
        if self.start is not None:
            if self.achieved:
                return 1.0
            # Do peso inicial até o alvo; andar para o lado errado conta zero.
            path = self.start - self.target if self.lower_is_better else self.target - self.start
            done = self.start - self.current if self.lower_is_better else self.current - self.start
            return 0.0 if path <= 0 else max(0.0, min(1.0, round(done / path, 4)))
        if self.lower_is_better:
            return 1.0 if self.current <= 0 else min(1.0, round(self.target / self.current, 4))
        return min(1.0, round(self.current / self.target, 4)) if self.target > 0 else None


@dataclass(frozen=True)
class GoalFacts:
    """O que os registros dizem sobre uma meta (o serviço preenche só o que ela usa)."""

    best_load_kg: float | None = None  # strength: maior carga com reps >= alvo
    weekly_sets: float | None = None  # hypertrophy: séries ponderadas/semana (28 dias)
    longest_run_m: int | None = None  # run_distance
    best_pace_s_per_km: float | None = None  # run_time: corridas da distância ou mais
    week_sessions: int | None = None  # frequency: nesta semana
    latest_weight_kg: float | None = None  # peso (5.3): o último registrado
    latest_weight_on: date | None = None
    start_weight_kg: float | None = None  # o de quando a meta começou


def progress(kind: str, target: dict, facts: GoalFacts, start: date) -> Progress | None:
    """Progresso medido pelos registros desde o início da meta. Hábito e metas livres
    não têm como ser medidos aqui (sem dado, sem número inventado): nulo."""
    since = start.strftime("%d/%m/%Y")
    if kind in ("weight_loss", "weight_gain", "weight_maintenance"):
        on = facts.latest_weight_on
        basis = "último peso registrado" if on is None else f"peso registrado em {on:%d/%m/%Y}"
        if kind == "weight_maintenance":
            return Progress(
                facts.latest_weight_kg,
                float(target["target_weight_kg"]),
                "kg",
                basis,
                tolerance=float(target["tolerance_kg"]),
            )
        return Progress(
            facts.latest_weight_kg,
            float(target["target_weight_kg"]),
            "kg",
            basis,
            lower_is_better=kind == "weight_loss",
            start=facts.start_weight_kg,
        )
    match kind:
        case "strength":
            return Progress(
                facts.best_load_kg,
                float(target["load_kg"]),
                "kg",
                f"maior carga em séries de {target['reps']}+ repetições desde {since}",
            )
        case "hypertrophy":
            return Progress(
                facts.weekly_sets,
                float(target["weekly_sets"]),
                "sets_per_week",
                "séries ponderadas por semana nos últimos 28 dias",
            )
        case "run_distance":
            return Progress(
                None if facts.longest_run_m is None else round(facts.longest_run_m / 1000, 2),
                float(target["distance_km"]),
                "km",
                f"corrida mais longa desde {since}",
            )
        case "run_time":
            km = float(target["distance_km"])
            pace = facts.best_pace_s_per_km
            return Progress(
                None if pace is None else round(pace * km),
                float(target["time_s"]),
                "s",
                f"tempo pelo melhor pace em corridas de {_km(km)} km ou mais desde {since}",
                lower_is_better=True,
            )
        case "frequency":
            return Progress(
                facts.week_sessions,
                float(target["sessions_per_week"]),
                "sessions",
                "treinos nesta semana (segunda a hoje)",
            )
    return None


def _km(value: float) -> str:
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return text.replace(".", ",")
