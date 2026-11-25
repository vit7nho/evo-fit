"""A única ferramenta que não é só de leitura (AI_DESIGN §3): cria uma proposta
`pending`. Nada muda nas fichas ou metas até a pessoa confirmar no app (ADR-053)."""

from typing import Any

from pydantic import Field

from app.modules.ai_coach import proposals
from app.modules.ai_coach.tools.base import Tool, ToolContext, ToolInput


class ProposalInput(ToolInput):
    change: proposals.Change = Field(
        description=(
            "A alteração: template_add_exercise, template_replace_exercise, "
            "template_adjust_sets (ids de get_templates; exercícios de search_exercises) "
            "ou goal_create."
        )
    )
    rationale: proposals.Rationale = Field(
        description="Por que sugerir isso, com base nos dados consultados (até 300 caracteres)."
    )


def prepare_change_proposal(ctx: ToolContext, args: ProposalInput) -> dict[str, Any]:
    proposal = proposals.prepare(ctx, args.change, args.rationale)
    return {
        "proposal_id": proposal.id,
        "status": "pending",
        "summary": proposal.summary,
        "details": proposal.details,
        "expires_in_days": proposals.EXPIRES_AFTER.days,
        "note": (
            "Ainda não foi aplicada: o app mostra a proposta com os botões Confirmar e "
            "Recusar. Diga isso à pessoa; não diga que a alteração já foi feita."
        ),
    }


TOOLS = (
    Tool(
        name="prepare_change_proposal",
        description=(
            "Propõe uma alteração em ficha de treino ou uma meta nova. Não altera nada: "
            "cria uma proposta que a pessoa confirma ou recusa no app."
        ),
        input_model=ProposalInput,
        handler=prepare_change_proposal,
    ),
)
