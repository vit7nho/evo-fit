"""`get_profile_summary`: o mínimo do perfil para a IA personalizar a resposta.

Fora, sempre: nome, e-mail, ano de nascimento e sexo (AI_DESIGN §8). O texto livre
das limitações só vai quando o modelo pede (a pergunta trata de limitações ou dor)
e com o consentimento `health_data` ativo — e nunca quando o provedor está no plano
gratuito (ADR-056). As etiquetas de limitação vão sempre, porque orientam a
segurança da resposta.
"""

from typing import Any

from pydantic import Field

from app.modules.ai_coach.tools.base import Tool, ToolContext, ToolInput
from app.modules.users import vocabulary
from app.modules.users.models import ConsentKind
from app.modules.users.service import active_consent


class ProfileInput(ToolInput):
    include_limitations_note: bool = Field(
        default=False,
        description=(
            "Inclui o texto livre sobre limitações. Use só quando a pergunta tratar de "
            "limitações, dor ou lesão."
        ),
    )


def _labels(codes: list[str] | None, names: dict[str, str]) -> list[str]:
    return [names.get(c, c) for c in codes or []]


def profile_summary(ctx: ToolContext, args: ProfileInput) -> dict[str, Any]:
    profile = ctx.user.profile
    if profile is None:
        return {"profile": None, "note": "A pessoa ainda não preencheu o perfil."}
    consent = active_consent(ctx.db, ctx.user.id, ConsentKind.HEALTH_DATA) is not None
    result: dict[str, Any] = {
        "primary_objective": vocabulary.OBJECTIVES.get(profile.primary_objective or "")
        if profile.primary_objective
        else None,
        "secondary_objectives": _labels(profile.secondary_objectives, vocabulary.OBJECTIVES),
        "modalities": _labels(profile.preferred_modalities, vocabulary.MODALITIES),
        "experience_level": vocabulary.EXPERIENCE_LEVELS.get(profile.experience_level.value)
        if profile.experience_level
        else None,
        "weekly_availability": profile.weekly_availability,
        "equipment": _labels(profile.equipment, vocabulary.EQUIPMENT),
        "limitation_tags": _labels(profile.limitation_tags, vocabulary.LIMITATION_TAGS),
        "units": "métrico (kg, km)",
        "timezone": profile.timezone,
        "today": ctx.today,
    }
    if args.include_limitations_note:
        if ctx.withhold_health_notes:
            result["limitations_note"] = None
            result["limitations_note_status"] = (
                "não enviado: o provedor de IA está no plano gratuito; use as etiquetas"
            )
        elif not consent:
            result["limitations_note"] = None
            result["limitations_note_status"] = "sem consentimento para dados de saúde"
        else:
            result["limitations_note"] = profile.limitations_note
    return result


TOOLS = (
    Tool(
        name="get_profile_summary",
        description=(
            "Resumo do perfil: objetivos, modalidades, experiência, disponibilidade por "
            "semana, equipamentos e limitações informadas (etiquetas). Também diz a data "
            "de hoje no fuso da pessoa."
        ),
        input_model=ProfileInput,
        handler=profile_summary,
    ),
)
