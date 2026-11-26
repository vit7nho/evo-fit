"""`get_nutrition_summary` (5.4, ADR-061): o que a pessoa registrou de alimentação no
período, a média dos dias com refeição e as metas que valiam. Só números: nenhum nome
de alimento nem observação sai daqui."""

from datetime import timedelta
from typing import Any

from app.modules.ai_coach.tools.base import MAX_ITEMS, PeriodInput, Tool, ToolContext, ToolError
from app.modules.nutrition.service import SUMMARY_MAX_DAYS, TargetService

DEFAULT_DAYS = 7


class NutritionInput(PeriodInput):
    """Sem datas: os últimos 7 dias até hoje."""


def _targets(targets: Any) -> dict[str, Any] | None:
    if targets is None:
        return None
    return {
        "valid_from": targets.valid_from,
        "kcal": targets.kcal,
        "protein_g": targets.protein_g,
        "carbs_g": targets.carbs_g,
        "fat_g": targets.fat_g,
    }


def nutrition_summary(ctx: ToolContext, args: NutritionInput) -> dict[str, Any]:
    end = args.to_date or ctx.today
    start = args.from_date or end - timedelta(days=DEFAULT_DAYS - 1)
    if (end - start).days + 1 > SUMMARY_MAX_DAYS:
        raise ToolError(f"Use um período de até {SUMMARY_MAX_DAYS} dias para a alimentação.")
    summary = TargetService(ctx.db).summary(ctx.user, start, end)
    logged = [d for d in summary.days if d.meals]
    return {
        "from_date": summary.from_date,
        "to_date": summary.to_date,
        "total_days": len(summary.days),
        # Dias com ao menos uma refeição registrada (a cobertura do período).
        "logged_days": summary.logged_days,
        "daily_average": None if summary.average is None else summary.average.model_dump(),
        "targets_now": _targets(summary.days[-1].targets),
        "days": [
            {
                "date": d.date,
                "meals": d.meals,
                "totals": d.totals.model_dump(),
                "targets": _targets(d.targets),
            }
            for d in logged[-MAX_ITEMS:]
        ],
        "truncated": len(logged) > MAX_ITEMS,
    }


TOOLS = (
    Tool(
        name="get_nutrition_summary",
        description=(
            "Alimentação registrada pela pessoa no período (padrão: últimos 7 dias): dias "
            "com refeição, média diária de calorias, proteína, carboidratos, gordura e "
            "fibras desses dias, e as metas diárias que ela definiu (as de hoje e as de "
            "cada dia). Fibra nula = não registrada."
        ),
        input_model=NutritionInput,
        handler=nutrition_summary,
    ),
)
