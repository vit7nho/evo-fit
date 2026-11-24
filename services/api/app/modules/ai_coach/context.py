"""Cartão de contexto mínimo (AI_DESIGN §2): a data de hoje, o fuso e o foco da
conversa. Nada de dados da pessoa aqui — nome, e-mail e registros só chegam ao
modelo pelas ferramentas, quando a pergunta pede."""

from datetime import date
from typing import Any

from app.modules.exercises import catalog

WEEKDAYS = ("segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo")

_FOCUS = {
    "session": "um treino específico (session_id {session_id}); comece por get_session_detail",
    "exercise": "um exercício (exercise_id {exercise_id}); comece por get_exercise_history",
    "activity": "uma atividade (activity_id {activity_id}); use get_activities no dia dela",
    "period": "o período de {from_date} a {to_date}; use essas datas nas ferramentas",
}


def focus(scope: str, ref: dict[str, Any] | None) -> str:
    ref = ref or {}
    if scope == "global":
        return "visão geral: combine as ferramentas que a pergunta pedir"
    if scope == "muscle":
        name = catalog.MUSCLE_NAMES.get(ref.get("muscle_id", ""), ref.get("muscle_id"))
        muscle_id = ref.get("muscle_id")
        text = f"o músculo {name} (muscle_id {muscle_id}); comece por get_muscle_stimulus"
        if ref.get("from_date") and ref.get("to_date"):
            text += f", no período de {ref['from_date']} a {ref['to_date']}"
        return text
    return _FOCUS[scope].format(**ref)


def context_card(today: date, timezone: str, scope: str, ref: dict[str, Any] | None) -> str:
    return "\n".join(
        [
            "## Contexto desta conversa",
            f"- Hoje: {today.isoformat()} ({WEEKDAYS[today.weekday()]}), fuso {timezone}.",
            f"- Foco: {focus(scope, ref)}.",
            "- Unidades: kg, km, minutos; pace em min/km.",
        ]
    )
