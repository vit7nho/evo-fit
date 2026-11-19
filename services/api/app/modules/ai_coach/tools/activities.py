"""`get_activities`: corridas, caminhadas, pedaladas e natações do período, com as
métricas presentes — o que não foi registrado vem nulo, nunca estimado."""

from typing import Any, Literal

from pydantic import Field

from app.modules.activities import router as activities_api
from app.modules.activities.service import ActivityService
from app.modules.ai_coach.tools.base import MAX_ITEMS, PeriodInput, Tool, ToolContext
from app.modules.ai_coach.tools.workouts import _bounds, _local

# Notas são texto livre da pessoa: vão cortadas, só para contexto.
NOTES_MAX = 200


class ActivitiesInput(PeriodInput):
    modality: Literal["run", "walk", "cycle", "swim"] | None = None
    limit: int = Field(default=MAX_ITEMS, ge=1, le=MAX_ITEMS, description="Quantas (1 a 30).")


def activities(ctx: ToolContext, args: ActivitiesInput) -> dict[str, Any]:
    start, end = args.period(ctx)
    lower, upper = _bounds(ctx, start, end)
    # Uma a mais para saber se cortou; o serviço já filtra o dono e as excluídas.
    found = [
        a
        for a in ActivityService(ctx.db).list(
            ctx.user, modality=args.modality, before=upper, limit=args.limit + 1
        )
        if a.started_at >= lower
    ]
    items = []
    for activity in found[: args.limit]:
        out = activities_api._out(activity)
        items.append(
            {
                "modality": out.modality,
                "started_at": _local(ctx, out.started_at),
                "duration_s": out.duration_s,
                "distance_m": out.distance_m,
                "pace_s_per_km": out.pace_s_per_km,
                "speed_kmh": out.speed_kmh,
                "pace_s_per_100m": out.pace_s_per_100m,
                "perceived_effort": out.perceived_effort,
                "elevation_gain_m": out.elevation_gain_m,
                "avg_hr": out.avg_hr,
                "max_hr": out.max_hr,
                "notes": out.notes[:NOTES_MAX] if out.notes else None,
            }
        )
    return {
        "from_date": start,
        "to_date": end,
        "items": items,
        "truncated": len(found) > args.limit,
    }


TOOLS = (
    Tool(
        name="get_activities",
        description=(
            "Atividades de resistência no período, da mais recente: modalidade, início, "
            "duração, distância, pace/velocidade, esforço, elevação, FC e notas. Campos "
            "não registrados vêm nulos."
        ),
        input_model=ActivitiesInput,
        handler=activities,
    ),
)
