"""`get_goals`: metas com o progresso medido pelos registros — o mesmo cálculo do
painel do Início (3.8), para a IA e a tela nunca discordarem."""

from typing import Any, Literal

from pydantic import Field

from app.modules.ai_coach.tools.base import Tool, ToolContext, ToolInput, capped
from app.modules.analytics.metrics import week_start
from app.modules.analytics.service import AnalyticsService
from app.modules.dashboard.router import GoalMeasurer, goal_card
from app.modules.goals.models import GoalStatus
from app.modules.goals.service import GoalService


class GoalsInput(ToolInput):
    status: Literal["active", "achieved", "abandoned"] | None = Field(
        default="active", description="Situação das metas. Padrão: as ativas; nulo = todas."
    )


def goals(ctx: ToolContext, args: GoalsInput) -> dict[str, Any]:
    status = GoalStatus(args.status) if args.status else None
    found = GoalService(ctx.db).list(ctx.user, status)
    day = ctx.today
    analytics = AnalyticsService(ctx.db)
    week = analytics.entries(ctx.user, week_start(day), day)
    measurer = GoalMeasurer(ctx.db, analytics, ctx.user, day)
    items = []
    for goal in found:
        card = goal_card(goal, measurer.for_goal(goal, week))
        items.append(
            {
                "id": goal.id,
                "kind": goal.kind,
                "title": goal.title,
                "target": card.summary,
                "status": goal.status.value,
                "priority": {1: "alta", 2: "média", 3: "baixa"}.get(goal.priority),
                "start_date": goal.start_date,
                "target_date": goal.target_date,
                # Medido pelos registros desde o início da meta; nulo quando o tipo não
                # é medido (peso, hábito, livre) e `current` nulo quando ainda não há
                # registro que meça. A IA não marca meta como alcançada.
                "progress": card.progress.model_dump() if card.progress else None,
            }
        )
    return capped(items)


TOOLS = (
    Tool(
        name="get_goals",
        description=(
            "Metas da pessoa com o alvo e o progresso medido pelos registros (atual, alvo, "
            "unidade, fração atingida e de onde vem o número). Progresso nulo = tipo que "
            "os registros não medem."
        ),
        input_model=GoalsInput,
        handler=goals,
    ),
)
