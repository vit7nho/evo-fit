"""Templates determinísticos e versionados dos planos (DATA_MODEL §4, ADR-041).

Um plano gerado guarda a versão do template e a cópia das prescrições: mudar um template
aqui (com versão nova) nunca altera um plano já começado. A IA não gera planos; no
máximo explica ou propõe ajustes (Fase 4).

Prescrição de uma sessão: lista de blocos. Um bloco é um passo
`{"type": "walk"|"run", "s": segundos, "effort"?: "easy"|"steady", "m"?: metros}`
ou uma repetição `{"repeat": n, "steps": [passos]}`.
"""

from collections.abc import Callable
from dataclasses import dataclass

Step = dict[str, object]
Block = dict[str, object]
Session = list[Block]
Week = list[Session]

WARMUP = 5 * 60


def walk(minutes: float, effort: str | None = None) -> Step:
    step: Step = {"type": "walk", "s": round(minutes * 60)}
    if effort:
        step["effort"] = effort
    return step


def run(minutes: float, effort: str | None = None, meters: int | None = None) -> Step:
    step: Step = {"type": "run", "s": round(minutes * 60)}
    if effort:
        step["effort"] = effort
    if meters:
        step["m"] = meters
    return step


def repeat(times: int, *steps: Step) -> Block:
    return {"repeat": times, "steps": list(steps)}


def framed(*blocks: Block) -> Session:
    """Aquecimento e volta à calma caminhando, em toda sessão com corrida."""
    return [walk(5), *blocks, walk(5)]


def intervals(times: int, run_min: float, walk_min: float, effort: str | None = None) -> Session:
    return framed(repeat(times, run(run_min, effort), walk(walk_min)))


@dataclass(frozen=True)
class PlanTemplate:
    kind: str
    version: int
    title: str
    summary: str
    # Modalidade das atividades que contam para as sessões.
    modality: str
    prerequisite: str | None
    weeks: tuple[Week, ...]
    sessions_per_week: int = 3

    @property
    def runs(self) -> bool:
        return self.modality == "run"


def _walk_habit() -> tuple[Week, ...]:
    # Duas caminhadas firmes e uma mais longa por semana, de 20 a 50 minutos.
    base = (20, 20, 25, 25, 30, 30, 35, 40)
    return tuple([[walk(m, "steady")], [walk(m, "steady")], [walk(m + 10, "easy")]] for m in base)


def _run_5k() -> tuple[Week, ...]:
    # Intervalos de corrida e caminhada até 30 minutos seguidos; a última sessão é o 5 km.
    same: Callable[[Session], Week] = lambda s: [s, s, s]  # noqa: E731
    return (
        same(intervals(8, 1, 1.5)),
        same(intervals(6, 1.5, 2)),
        same(intervals(5, 2, 1.5)),
        same(intervals(4, 4, 2)),
        [intervals(3, 6, 2), intervals(3, 6, 2), intervals(2, 10, 3)],
        [intervals(2, 10, 2), intervals(2, 12, 2), framed(run(20))],
        same(framed(run(25))),
        same(framed(run(28))),
        [framed(run(30)), framed(run(30)), framed(run(35, meters=5000))],
    )


def _run_10k() -> tuple[Week, ...]:
    # Para quem já corre 5 km: rodagem leve, um treino de ritmo e um longão por semana.
    easy = (30, 30, 35, 35, 40, 40, 35, 30)
    quality: tuple[Session, ...] = (
        intervals(4, 3, 2, "steady"),
        intervals(5, 3, 2, "steady"),
        intervals(4, 5, 2, "steady"),
        intervals(3, 7, 2, "steady"),
        framed(run(20, "steady")),
        framed(repeat(2, run(12, "steady"), run(3, "easy"))),
        framed(run(25, "steady")),
        intervals(3, 4, 2, "steady"),
    )
    long_runs = (40, 45, 50, 55, 60, 65, 50)
    weeks = [[[run(easy[i], "easy")], quality[i], [run(long_runs[i], "easy")]] for i in range(7)]
    weeks.append([[run(easy[7], "easy")], quality[7], framed(run(65, meters=10_000))])
    return tuple(weeks)


TEMPLATES: dict[str, PlanTemplate] = {
    t.kind: t
    for t in (
        PlanTemplate(
            kind="walk_habit",
            version=1,
            title="Hábito de caminhada",
            summary="Caminhadas de 20 a 50 minutos para criar o hábito.",
            modality="walk",
            prerequisite=None,
            weeks=_walk_habit(),
        ),
        PlanTemplate(
            kind="run_5k",
            version=1,
            title="Primeiros 5 km",
            summary="Corrida alternada com caminhada até correr 5 km sem parar.",
            modality="run",
            prerequisite="Para quem já caminha 30 minutos sem desconforto.",
            weeks=_run_5k(),
        ),
        PlanTemplate(
            kind="run_10k",
            version=1,
            title="Rumo aos 10 km",
            summary="Rodagem, treino de ritmo e longão até completar os 10 km.",
            modality="run",
            prerequisite="Para quem já corre 5 km (ou 30 minutos) sem parar.",
            weeks=_run_10k(),
        ),
    )
}


def session_seconds(session: Session) -> int:
    total = 0
    for block in session:
        if "repeat" in block:
            total += block["repeat"] * sum(s["s"] for s in block["steps"])  # type: ignore[misc,union-attr]
        else:
            total += block["s"]  # type: ignore[operator]
    return total


def _duration(seconds: int) -> str:
    minutes, rest = divmod(seconds, 60)
    return f"{minutes}:{rest:02d}" if rest else f"{minutes} min"


_EFFORT = {
    ("run", "easy"): " leve",
    ("run", "steady"): " moderado",
    ("walk", "easy"): " leve",
    ("walk", "steady"): " em ritmo firme",
}


def _step_text(step: Step) -> str:
    verb = "correndo" if step["type"] == "run" else "caminhando"
    if "m" in step:
        return f"{step['m'] / 1000:g} km {verb}".replace(".", ",")
    effort = _EFFORT.get((step["type"], step.get("effort")), "")  # type: ignore[arg-type]
    return f"{_duration(step['s'])} {verb}{effort}"  # type: ignore[arg-type]


def describe(session: Session) -> str:
    """Resumo em texto, ex.: "5 min caminhando · 8x (1 min correndo + 1:30 caminhando) · …"."""
    parts = []
    for block in session:
        if "repeat" in block:
            inner = " + ".join(_step_text(s) for s in block["steps"])  # type: ignore[union-attr]
            parts.append(f"{block['repeat']}x ({inner})")
        else:
            parts.append(_step_text(block))
    return " · ".join(parts)
