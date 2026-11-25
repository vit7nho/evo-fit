"""Fichas de treino da pessoa (4.6): o que a IA precisa ler antes de propor uma
alteração — ids das fichas e dos itens, exercícios e séries planejadas."""

from typing import Any

from app.modules.ai_coach.proposals import describe_sets
from app.modules.ai_coach.tools.base import Tool, ToolContext, ToolInput, capped
from app.modules.training.catalog import GROUP_KINDS
from app.modules.training.schemas import PlannedSet
from app.modules.training.service import TemplateService


class TemplatesInput(ToolInput):
    pass


def templates(ctx: ToolContext, args: TemplatesInput) -> dict[str, Any]:
    out = []
    for template in TemplateService(ctx.db).list(ctx.user):
        groups = {g.id: GROUP_KINDS.get(g.kind, g.kind) for g in template.groups}
        out.append(
            {
                "template_id": template.id,
                "name": template.name,
                "items": [
                    {
                        "item_id": item.id,
                        "exercise_id": item.exercise_id,
                        "exercise": item.exercise.name,
                        "primary_muscles": [
                            m.muscle_group_id for m in item.exercise.muscles if m.role == "primary"
                        ],
                        "planned_sets": item.planned_sets,
                        "sets_text": describe_sets(
                            [PlannedSet.model_validate(s) for s in item.planned_sets]
                        ),
                        "rest_s": item.rest_s,
                        "group": groups.get(item.group_id) if item.group_id else None,
                    }
                    for item in sorted(template.items, key=lambda i: i.position)
                ],
            }
        )
    return capped(out)


TOOLS = (
    Tool(
        name="get_templates",
        description=(
            "Fichas de treino da pessoa, com os ids das fichas e dos itens, os exercícios, "
            "os músculos principais e as séries planejadas. Use antes de propor alteração."
        ),
        input_model=TemplatesInput,
        handler=templates,
    ),
)
