"""`get_body_trend` (5.4, ADR-061): peso e medidas no período — um ponto por dia, a
média de 7 dias, a variação e o ritmo por semana, como na tela Peso e medidas. As
observações (texto livre) não saem daqui."""

from datetime import timedelta
from typing import Any

from pydantic import Field

from app.modules.ai_coach.tools.base import MAX_ITEMS, PeriodInput, Tool, ToolContext
from app.modules.body.models import METRICS
from app.modules.body.schemas import Metric
from app.modules.body.service import INFO, MeasurementService

DEFAULT_DAYS = 90


class BodyTrendInput(PeriodInput):
    """Sem datas: os últimos 90 dias até hoje."""

    metric: Metric = Field(
        default="weight_kg",
        description=(
            "weight_kg (peso), body_fat_pct (gordura, estimativa), waist_cm, hip_cm, "
            "chest_cm, arm_cm, thigh_cm ou calf_cm."
        ),
    )


def _point(point: Any) -> dict[str, Any] | None:
    if point is None:
        return None
    return {"date": point.date, "value": point.value, "average_7d": point.average_7d}


def body_trend(ctx: ToolContext, args: BodyTrendInput) -> dict[str, Any]:
    end = args.to_date or ctx.today
    start = args.from_date or end - timedelta(days=DEFAULT_DAYS - 1)
    service = MeasurementService(ctx.db)
    trend = service.trend(ctx.user, args.metric, start, end)
    rows = service.list(ctx.user, start, end)
    return {
        "metric": trend.metric,
        "label": trend.label,
        "unit": trend.unit,
        "estimate": INFO[args.metric].estimate,
        "from_date": trend.from_date,
        "to_date": trend.to_date,
        # Que medidas têm registro no período (para consultar as outras).
        "recorded_metrics": [m for m in METRICS if any(getattr(r, m) is not None for r in rows)],
        "points": [_point(p) for p in trend.points[-MAX_ITEMS:]],
        "truncated": len(trend.points) > MAX_ITEMS,
        "first": _point(trend.first),
        "last": _point(trend.last),
        "change": trend.change,
        "min": trend.min,
        "max": trend.max,
        "weekly_rate": trend.weekly_rate,
    }


TOOLS = (
    Tool(
        name="get_body_trend",
        description=(
            "Peso ou uma medida do corpo no período (padrão: últimos 90 dias): um ponto "
            "por dia com registro, média de 7 dias, primeiro e último valor, variação, "
            "mínimo, máximo e ritmo por semana (nulo com poucos pontos). Diz também quais "
            "medidas têm registro. Gordura corporal é estimativa."
        ),
        input_model=BodyTrendInput,
        handler=body_trend,
    ),
)
