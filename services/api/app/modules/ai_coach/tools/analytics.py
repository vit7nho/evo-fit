"""Ferramentas do motor de análise: estímulo muscular, comparação de períodos e
progresso de resistência. Chamam as mesmas funções dos endpoints `/analytics/*`
(3.4 a 3.7): os números da IA e das telas são, por construção, os mesmos."""

from datetime import date
from typing import Any, Literal

from pydantic import Field

from app.modules.ai_coach.tools.base import PeriodInput, Tool, ToolContext, ToolError, ToolInput
from app.modules.analytics import router as analytics_api
from app.modules.exercises import catalog

Modality = Literal["run", "walk", "cycle", "swim"]
Metric = Literal[
    "sessions",
    "active_days",
    "duration_s",
    "strength_sets",
    "strength_volume_kg",
    "distance_m",
    "pace_s_per_km",
]

# --- get_muscle_stimulus ---


class StimulusInput(PeriodInput):
    muscle_ids: list[str] | None = Field(
        default=None,
        max_length=3,
        description=(
            "Até 3 músculos para trazer também os exercícios e a comparação com o período "
            "anterior (chest, delts, biceps, triceps, forearms, abs, obliques, traps, "
            "lats, glutes, quads, hamstrings, calves). Sem isso: os 13, resumidos."
        ),
    )


def muscle_stimulus(ctx: ToolContext, args: StimulusInput) -> dict[str, Any]:
    start, end = args.period(ctx)
    unknown = [m for m in args.muscle_ids or [] if m not in catalog.MUSCLE_NAMES]
    if unknown:
        raise ToolError(f"Músculo desconhecido: {', '.join(unknown)}.")
    body = analytics_api.muscles(ctx.user, ctx.db, start, end)
    result: dict[str, Any] = {
        "methodology_version": body.methodology_version,
        "from_date": body.from_date,
        "to_date": body.to_date,
        "period_days": body.period_days,
        "bands_weekly_sets": body.bands,
        "notice": body.notice,
        "muscles": [
            {
                "muscle_id": m.muscle_id,
                "name": m.name,
                "weighted_sets_per_week": m.weighted_sets_per_week,
                "band": m.band,
                "frequency_days": m.frequency,
                "volume_load_kg": m.volume_load_kg,
            }
            for m in body.muscles
        ],
    }
    if args.muscle_ids:
        details = []
        for muscle_id in args.muscle_ids:
            d = analytics_api.muscle_detail(muscle_id, ctx.user, ctx.db, start, end, "previous")
            details.append(
                {
                    "muscle_id": muscle_id,
                    "exercises": [e.model_dump(exclude={"exercise_id"}) for e in d.exercises],
                    "previous_period": d.previous.model_dump() if d.previous else None,
                }
            )
        result["details"] = details
    return result


# --- compare_periods ---


class PeriodRange(ToolInput):
    from_date: date
    to_date: date


class CompareInput(ToolInput):
    metric: Metric = Field(
        description=(
            "Indicador. distance_m e pace_s_per_km exigem modality; pace só corrida ou "
            "caminhada (menor é melhor)."
        )
    )
    period_a: PeriodRange = Field(description="A base do percentual (normalmente o anterior).")
    period_b: PeriodRange = Field(description="O período comparado com A.")
    modality: Modality | None = None


def compare_periods(ctx: ToolContext, args: CompareInput) -> dict[str, Any]:
    out = analytics_api.compare(
        args.metric,
        ctx.user,
        ctx.db,
        args.period_a.from_date,
        args.period_a.to_date,
        args.period_b.from_date,
        args.period_b.to_date,
        args.modality,
    )
    data = out.model_dump()
    # O percentual só existe com base válida (A > 0): de 0 para 3 não é “+∞%”.
    data["percent_rule"] = "percentual só quando o valor de A é maior que zero"
    return data


# --- get_endurance_progress ---


class EnduranceInput(PeriodInput):
    modality: Modality


def endurance_progress(ctx: ToolContext, args: EnduranceInput) -> dict[str, Any]:
    start, end = args.period(ctx)
    out = analytics_api.endurance(args.modality, ctx.user, ctx.db, start, end)
    data = out.model_dump()
    data["notes"] = (
        "Pace e velocidade ponderados (tempo total ÷ distância total, só atividades com "
        "distância); nulos sem distância. A tendência usa só semanas inteiras."
    )
    return data


TOOLS = (
    Tool(
        name="get_muscle_stimulus",
        description=(
            "Meu Corpo: séries ponderadas por semana, faixa (none, low, mid, high), "
            "frequência e volume de cada músculo no período, com a versão da metodologia "
            "e o aviso de que é referência, não diagnóstico."
        ),
        input_model=StimulusInput,
        handler=muscle_stimulus,
    ),
    Tool(
        name="compare_periods",
        description=(
            "Compara um indicador entre dois períodos: valores de A e B, diferença, "
            "percentual (só com base válida) e qual foi melhor."
        ),
        input_model=CompareInput,
        handler=compare_periods,
    ),
    Tool(
        name="get_endurance_progress",
        description=(
            "Corrida, caminhada, ciclismo ou natação no período: totais, pace ou "
            "velocidade médios, cada semana e a tendência da distância semanal."
        ),
        input_model=EnduranceInput,
        handler=endurance_progress,
    ),
)
