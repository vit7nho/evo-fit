"""Provedor de demonstração (ADR-058): o assistente sem IA externa.

Para apresentar o EvoFit sem internet, sem chave e sem cota. Ele segue o mesmo
caminho de um modelo de verdade — pede as ferramentas ao orquestrador, que as roda
com o usuário autenticado, e responde a partir dos resultados —, mas decide **por
regras**: palavras-chave escolhem a intenção, a intenção escolhe as ferramentas, e
um modelo de texto monta a resposta com os números que as ferramentas devolveram.

O que isso garante: os números vêm dos registros da pessoa (passam pela mesma
conferência das respostas da IA), propostas só são criadas como pendentes, dor,
dieta e hormônio vão para um profissional, e nada sai do servidor. O que não faz:
entender perguntas fora do roteiro — nesses casos ele diz o que sabe responder.

Sem estado entre chamadas: cada chamada olha a última pergunta e as ferramentas já
consultadas depois dela, e decide o passo seguinte. Funciona sozinho
(`AI_PROVIDER=demo`) ou como reserva no fim da cadeia (`gemini,groq,demo`).
"""

import copy
import json
import re
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any

from app.integrations.ai.provider import Completion, Message, ToolCall, ToolSpec, Usage
from app.integrations.ai.providers.fake import estimate_tokens

DEMO_MODEL = "demo-v1"

# Uma chamada da ferramenta: (nome, argumentos).
Call = tuple[str, dict[str, Any]]


def normalize(text: str) -> str:
    """Minúsculas, sem acentos e sem pontuação nas pontas."""
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in decomposed if not unicodedata.combining(c)).strip(" ?!.")


# --- formatação (números no padrão brasileiro) ---


def num(value: float, decimals: int = 1) -> str:
    """1200 → "1.200"; 0.47 → "0,5"; 11.0 → "11"."""
    rounded = round(float(value), decimals)
    if rounded.is_integer():
        return f"{int(rounded):,}".replace(",", ".")
    text = f"{rounded:,.{decimals}f}"
    return text.replace(",", "_").replace(".", ",").replace("_", ".")


def plural(count: float, one: str, many: str) -> str:
    """ "1 treino", "3 treinos", "0,5 série"."""
    return f"{num(count)} {one if 0 < count < 2 else many}"


def minutes(seconds: float | None) -> str:
    return f"{round((seconds or 0) / 60)} min"


def pace(seconds: int | None) -> str:
    return "—" if not seconds else f"{seconds // 60}:{seconds % 60:02d} /km"


def day(value: str | None) -> str:
    """ "2026-11-01" ou "2026-11-01T18:30-03:00" → "01/11"."""
    if not value:
        return "?"
    parsed = datetime.fromisoformat(value) if "T" in value else date.fromisoformat(value)
    return parsed.strftime("%d/%m")


# --- a pergunta da vez e o que já foi consultado ---


@dataclass
class Turn:
    question: str
    today: date
    results: dict[str, list[Any]] = field(default_factory=dict)
    calls: list[Call] = field(default_factory=list)
    # O foco da conversa (cartão de contexto): muscle, session, exercise, period.
    focus: dict[str, Any] = field(default_factory=dict)

    @property
    def q(self) -> str:
        return normalize(self.question)

    def has(self, name: str) -> bool:
        return name in self.results

    def last(self, name: str) -> Any:
        found = self.results.get(name)
        return found[-1] if found else None

    def period(self, days: int) -> dict[str, str]:
        if "period" in self.focus:
            start, end = self.focus["period"]
            return {"from_date": start, "to_date": end}
        return {
            "from_date": (self.today - timedelta(days=days - 1)).isoformat(),
            "to_date": self.today.isoformat(),
        }

    def days(self, default: int = 30) -> int:
        if "period" in self.focus:
            start, end = (date.fromisoformat(d) for d in self.focus["period"])
            return (end - start).days + 1
        q = self.q
        if match := re.search(r"(\d{1,3}) dias", q):
            return max(1, min(int(match.group(1)), 366))
        if "semana" in q:
            return 7
        if "ano" in q.split():
            return 365
        return default


_TODAY = re.compile(r"Hoje: (\d{4}-\d{2}-\d{2})")
_UUID = r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
_FOCUS = {
    "muscle": re.compile(r"\(muscle_id ([a-z_]+)\)"),
    "session": re.compile(rf"\(session_id {_UUID}\)"),
    "exercise": re.compile(rf"\(exercise_id {_UUID}\)"),
}
_PERIOD = re.compile(r"período de (\d{4}-\d{2}-\d{2}) a (\d{4}-\d{2}-\d{2})")


def read_focus(system: str) -> dict[str, Any]:
    """O foco escrito no cartão de contexto (`context.py`), quando não é geral."""
    line = next((li for li in system.splitlines() if li.startswith("- Foco:")), "")
    focus: dict[str, Any] = {
        key: match.group(1) for key, pattern in _FOCUS.items() if (match := pattern.search(line))
    }
    if match := _PERIOD.search(line):
        focus["period"] = (match.group(1), match.group(2))
    return focus


def read_turn(system: str, messages: list[Message]) -> Turn:
    match = _TODAY.search(system)
    today = date.fromisoformat(match.group(1)) if match else date.today()
    start = max((i for i, m in enumerate(messages) if m.role == "user"), default=-1)
    question = messages[start].content if start >= 0 else ""
    turn = Turn(question, today, focus=read_focus(system))
    asked: dict[str, ToolCall] = {}
    for message in messages[start + 1 :]:
        for call in message.tool_calls:
            asked[call.id] = call
            turn.calls.append((call.name, call.arguments))
        for result in message.tool_results:
            call = asked.get(result.call_id)
            if call is None:
                continue
            try:
                payload = json.loads(result.content)
            except ValueError:
                payload = {"error": "resultado ilegível"}
            turn.results.setdefault(call.name, []).append(payload)
    return turn


# --- vocabulário ---

MUSCLE_WORDS = (
    ("posterior", "hamstrings"),
    ("isquio", "hamstrings"),
    ("peit", "chest"),
    ("costas", "lats"),
    ("dorsa", "lats"),
    ("quadricep", "quads"),
    ("glute", "glutes"),
    ("ombro", "delts"),
    ("deltoide", "delts"),
    ("bicep", "biceps"),
    ("tricep", "triceps"),
    ("panturrilha", "calves"),
    ("abdom", "abs"),
    ("obliquo", "obliques"),
    ("trapezio", "traps"),
    ("antebraco", "forearms"),
)
MODALITIES = (
    ("corr", "run", "corrida"),
    ("caminh", "walk", "caminhada"),
    ("pedal", "cycle", "pedalada"),
    ("bike", "cycle", "pedalada"),
    ("bicicleta", "cycle", "pedalada"),
    ("ciclis", "cycle", "pedalada"),
    ("nata", "swim", "natação"),
    ("nad", "swim", "natação"),
)
MODALITY_NAMES = {"run": "corrida", "walk": "caminhada", "cycle": "pedalada", "swim": "natação"}
BANDS = {"none": "nenhuma", "low": "baixa", "mid": "moderada", "high": "alta"}
NOTE_REFERENCE = (
    "As faixas são uma referência pelo volume registrado (séries por semana), não um diagnóstico."
)


def muscle_in(q: str) -> str | None:
    words = q.split()
    for stem, muscle_id in MUSCLE_WORDS:
        if any(w.startswith(stem) for w in words):
            return muscle_id
    return None


def modality_in(q: str) -> tuple[str, str] | None:
    words = q.split()
    for stem, code, label in MODALITIES:
        if any(w.startswith(stem) for w in words):
            return code, label
    return None


def has_word(q: str, *stems: str) -> bool:
    return any(w.startswith(stems) for w in q.split())


# --- respostas sem consulta ---

OTHER_ACCOUNT = (
    "Só tenho acesso aos registros da **sua** conta: não consigo ver nem mostrar dados "
    "de outras pessoas. Posso ajudar com os seus treinos, atividades ou metas?"
)
PAIN = (
    "Não consigo avaliar dor nem dizer a causa dela pelo chat. Dor durante um "
    "exercício merece avaliação de um **profissional de saúde** — um médico ou um "
    "fisioterapeuta.\n\n"
    "Enquanto isso:\n"
    '- evite o movimento que provoca a dor, em vez de treinar "por cima" dela;\n'
    "- se quiser seguir treinando, escolha exercícios que não doem;\n"
    "- procure atendimento logo se a dor for forte, vier com inchaço ou não melhorar.\n\n"
    "Se você registrar a limitação no seu perfil, eu levo isso em conta nas sugestões."
)
DIET = (
    "Não monto dietas. Uma dieta muito restritiva, para perder peso rápido, pode fazer "
    "mal à saúde e costuma custar massa muscular. Quem pode montar um plano seguro para "
    "você é um **nutricionista**.\n\n"
    "Do meu lado, posso acompanhar seus treinos e metas — por exemplo, uma meta de "
    "frequência semanal ou de peso, com prazo realista."
)
HORMONE = (
    "Não posso indicar hormônios nem suplementos hormonais: o uso exige avaliação e "
    "acompanhamento **médico** (um endocrinologista, por exemplo).\n\n"
    "Para ganhar massa, posso ajudar com o que está nos seus registros: o volume de "
    "séries por músculo, a frequência e a evolução das cargas."
)
HELP = (
    "Sou o assistente de treino do EvoFit e consulto os seus registros para responder. "
    "Experimente perguntar:\n"
    "- O que fiz na minha última sessão?\n"
    "- Quais músculos treinei menos nos últimos 30 dias?\n"
    "- Compare minha última semana com a anterior.\n"
    "- Quanto corri nos últimos 30 dias?\n"
    "- Estou perto da minha meta?\n"
    "- Qual é o meu 1RM estimado no supino?\n"
    "- Adicione um exercício de posterior de coxa na minha ficha."
)
OUT_OF_SCOPE = "Só consigo ajudar com seus treinos, atividades, metas e hábitos.\n\n" + HELP


# --- intenções: cada uma devolve as próximas ferramentas ou o texto final ---

Step = list[Call] | str


def last_session(t: Turn) -> Step:
    if not t.has("get_workout_history"):
        return [("get_workout_history", {**t.period(366), "limit": 5})]
    history = t.last("get_workout_history")
    items = history.get("items") or []
    if not items:
        return (
            "Ainda não há registros de treino de musculação. Quando você terminar um "
            "treino no app, ele aparece aqui."
        )
    if not t.has("get_session_detail"):
        return [("get_session_detail", {"session_id": items[0]["session_id"]})]
    detail = t.last("get_session_detail")
    if "error" in detail:
        detail = {**items[0], "exercises": []}
    lines = _session_lines(detail, "Sua última sessão foi")
    more = history.get("total_sessions", 1) - 1
    if more > 0:
        lines.append(f"\nNo último ano há mais {plural(more, 'treino', 'treinos')} registrados.")
    return "\n".join(lines)


# Os tipos de recorde do histórico (history/service.py) e a unidade de cada um.
RECORD_KINDS = {
    "max_load": ("maior carga", " kg"),
    "best_e1rm": ("maior 1RM estimado", " kg"),
    "max_volume": ("maior volume", " kg"),
    "max_reps": ("mais repetições", ""),
    "max_duration": ("maior duração", " s"),
}


def _session_lines(detail: dict[str, Any], intro: str) -> list[str]:
    """O resumo de um treino (de get_session_detail), série por série."""
    lines = [
        f"{intro} **{detail.get('name') or 'Treino'}**, em "
        f"{day(detail.get('started_at'))}: {minutes(detail.get('duration_s'))}, "
        f"{plural(detail.get('sets', 0), 'série válida', 'séries válidas')} e "
        f"{num(detail.get('volume_kg', 0))} kg de volume."
    ]
    for exercise in detail.get("exercises", []):
        sets = [s for s in exercise.get("sets", []) if s.get("kind") != "warmup"]
        parts = []
        for s in sets:
            if s.get("reps") and s.get("load_kg") is not None:
                text = f"{num(s['load_kg'])} kg × {s['reps']}"  # noqa: RUF001
            elif s.get("reps"):
                text = f"{s['reps']} repetições"
            elif s.get("duration_s"):
                text = f"{s['duration_s']} s"
            else:
                continue
            if s.get("kind") == "drop":
                text += " (drop)"
            elif s.get("kind") == "rest_pause":
                text += " (rest-pause)"
            parts.append(text)
        if parts:
            lines.append(f"- **{exercise['name']}**: " + ", ".join(parts))
    records = detail.get("records") or []
    if records:
        lines.append("\nRecordes neste treino:")
        for r in records[:5]:
            kind, unit = RECORD_KINDS.get(r.get("kind"), (r.get("kind"), ""))
            value = f": {num(r['value'])}{unit}" if r.get("value") is not None else ""
            lines.append(f"- {r.get('exercise')}, {kind}{value}")
    return lines


def session_focus(t: Turn) -> Step:
    """Conversa sobre um treino (atalho do detalhe do treino)."""
    versus = has_word(t.q, "anterior", "mudou", "compar", "antes", "evolu")
    if not t.has("get_session_detail"):
        calls: list[Call] = [("get_session_detail", {"session_id": t.focus["session"]})]
        if versus:
            calls.append(("get_workout_history", {**t.period(366), "limit": 20}))
        return calls
    detail = t.last("get_session_detail")
    if "error" in detail:
        return f"Não consegui abrir esse treino: {detail['error']}"
    lines = _session_lines(detail, "Este treino foi")
    if has_word(t.q, "recorde") and not detail.get("records"):
        lines.append("\nNenhum recorde neste treino.")
    if versus:
        items = (t.last("get_workout_history") or {}).get("items") or []
        ids = [i["session_id"] for i in items]
        here = ids.index(detail["session_id"]) if detail.get("session_id") in ids else -1
        before = items[here + 1] if 0 <= here < len(items) - 1 else None
        if before is None:
            lines.append("\nNão há um treino anterior registrado para comparar.")
        else:
            lines.append(
                f"\nNo treino anterior ({before.get('name') or 'Treino'}, "
                f"{day(before['started_at'])}): "
                f"{plural(before.get('sets') or 0, 'série válida', 'séries válidas')} e "
                f"{num(before.get('volume_kg') or 0)} kg de volume, em "
                f"{minutes(before.get('duration_s'))}."
            )
    return "\n".join(lines)


def muscle_focus(t: Turn) -> Step:
    """Conversa sobre um músculo (atalho do Meu Corpo)."""
    muscle = t.focus["muscle"]
    if not t.has("get_muscle_stimulus"):
        return [("get_muscle_stimulus", {**t.period(30), "muscle_ids": [muscle]})]
    data = t.last("get_muscle_stimulus")
    if "error" in data:
        return f"Não consegui consultar o estímulo: {data['error']}"
    m = next((r for r in data.get("muscles") or [] if r["muscle_id"] == muscle), None)
    if m is None:
        return "Não encontrei esse músculo no mapa."
    details = next((d for d in data.get("details") or [] if d["muscle_id"] == muscle), {})
    if not m.get("weighted_sets_per_week"):
        lines = [
            f"Ainda não há registros de séries para **{m['name']}** de "
            f"{day(data['from_date'])} a {day(data['to_date'])}."
        ]
    else:
        lines = [
            f"**{m['name']}** de {day(data['from_date'])} a {day(data['to_date'])}: "
            f"{plural(m['weighted_sets_per_week'], 'série', 'séries')} por semana, faixa "
            f"**{BANDS.get(m['band'], m['band'])}**."
        ]
        exercises = sorted(
            details.get("exercises") or [], key=lambda e: e["weighted_sets"], reverse=True
        )
        if exercises:
            lines.append("\nOs exercícios que mais trabalharam esse músculo:")
            for e in exercises[:4]:
                role = "principal" if e["role"] == "primary" else "secundário"
                text = f"- **{e['name']}** ({role}): {plural(e['sets'], 'série', 'séries')}"
                if e.get("best_load_kg"):
                    text += f", maior carga {num(e['best_load_kg'])} kg"
                lines.append(text)
    previous = details.get("previous_period")
    if previous:
        text = (
            f"\nNo período anterior ({day(previous['from_date'])} a "
            f"{day(previous['to_date'])}): "
            f"{plural(previous['weighted_sets_per_week'], 'série', 'séries')} por semana "
            f"(faixa {BANDS.get(previous['band'], previous['band'])})"
        )
        diff = previous.get("difference") or 0
        if diff > 0:
            text += " — agora você treinou mais."
        elif diff < 0:
            text += " — agora você treinou menos."
        else:
            text += " — o mesmo volume."
        lines.append(text)
    return "\n".join(lines) + "\n\n" + NOTE_REFERENCE


def week_totals(t: Turn) -> Step:
    monday = t.today - timedelta(days=t.today.weekday())
    if not t.has("get_workout_history"):
        args = {"from_date": monday.isoformat(), "to_date": t.today.isoformat(), "limit": 20}
        return [("get_workout_history", args), ("get_activities", args)]
    items = t.last("get_workout_history").get("items") or []
    runs = (t.last("get_activities") or {}).get("items") or []
    since = monday.strftime("%d/%m")
    if not items and not runs:
        return f"Ainda não há registros nesta semana (desde {since}). Que tal registrar o próximo?"
    lines = [f"Nesta semana (desde {since}):"]
    if items:
        lines.append(f"\n**Musculação:** {plural(len(items), 'treino', 'treinos')}")
        lines += [
            f"- {day(i['started_at'])}, {i.get('name') or 'Treino'}: "
            f"{minutes(i.get('duration_s'))}, "
            f"{plural(i.get('sets') or 0, 'série válida', 'séries válidas')}, "
            f"{num(i.get('volume_kg') or 0)} kg de volume"
            for i in items
        ]
    if runs:
        lines.append(f"\n**Atividades:** {len(runs)}")
        lines += [
            f"- {day(r['started_at'])}, {MODALITY_NAMES.get(r['modality'], r['modality'])}: "
            f"{minutes(r.get('duration_s'))}"
            + (f", {num(r['distance_m'] / 1000)} km" if r.get("distance_m") else "")
            for r in runs
        ]
    return "\n".join(lines)


def compare_weeks(t: Turn) -> Step:
    if not t.has("compare_periods"):
        b = (t.today - timedelta(days=6), t.today)
        a = (t.today - timedelta(days=13), t.today - timedelta(days=7))

        def args(metric: str) -> dict[str, Any]:
            return {
                "metric": metric,
                "period_a": {"from_date": a[0].isoformat(), "to_date": a[1].isoformat()},
                "period_b": {"from_date": b[0].isoformat(), "to_date": b[1].isoformat()},
            }

        return [
            ("compare_periods", args("sessions")),
            ("compare_periods", args("duration_s")),
            ("compare_periods", args("strength_sets")),
        ]
    rows = [r for r in t.results["compare_periods"] if "error" not in r]
    if not rows:
        return "Não consegui comparar os períodos agora. Tente de novo em instantes."
    first = rows[0]
    lines = [
        f"Últimos 7 dias ({day(first['b']['from_date'])} a {day(first['b']['to_date'])}) "
        f"comparados com os 7 anteriores ({day(first['a']['from_date'])} a "
        f"{day(first['a']['to_date'])}):"
    ]
    if all(not r["a"]["value"] and not r["b"]["value"] for r in rows):
        return lines[0] + "\n\nAinda não há registros em nenhum dos dois períodos."
    for r in rows:
        show = minutes if r["metric"] == "duration_s" else (lambda v: num(v or 0))
        a, b = r["a"]["value"], r["b"]["value"]
        if r.get("percent") is not None:
            sign = "+" if r["percent"] > 0 else ""
            change = f"{sign}{num(r['percent'])}%"
        elif r.get("difference") == 0:
            change = "igual"
        else:
            change = "sem percentual: o período anterior foi zero"
        lines.append(f"- **{r['label']}:** {show(a)} → {show(b)} — {change}")
    better = [r for r in rows if r.get("better") == "b"]
    worse = [r for r in rows if r.get("better") == "a"]
    if better and not worse:
        lines.append("\nVocê treinou mais nesta semana. Bom ritmo!")
    elif worse and not better:
        lines.append("\nEsta semana teve menos treino que a anterior.")
    return "\n".join(lines)


def endurance(t: Turn, modality: tuple[str, str]) -> Step:
    code, label = modality
    days = t.days()
    if not t.has("get_endurance_progress"):
        return [("get_endurance_progress", {**t.period(days), "modality": code})]
    data = t.last("get_endurance_progress")
    if "error" in data:
        return f"Não consegui consultar suas atividades: {data['error']}"
    if not data.get("sessions"):
        return (
            f"Ainda não há registros de {label} nos últimos {days} dias. Quando você "
            "registrar uma atividade, eu acompanho a evolução."
        )
    lines = [
        f"Nos últimos {days} dias ({day(data['from_date'])} a {day(data['to_date'])}): "
        f"**{plural(data['sessions'], 'atividade', 'atividades')}** de {label}, "
        f"**{num(data['distance_m'] / 1000)} km** em {minutes(data['duration_s'])}."
    ]
    if code in ("run", "walk") and data.get("pace_s_per_km"):
        lines.append(f"- Pace médio: **{pace(data['pace_s_per_km'])}** (tempo ÷ distância).")
    elif data.get("speed_kmh"):
        lines.append(f"- Velocidade média: **{num(data['speed_kmh'])} km/h**.")
    trend = (data.get("distance_trend") or {}).get("direction")
    if trend:
        lines.append(
            "- Tendência da distância semanal: "
            + {"up": "subindo.", "down": "caindo.", "flat": "estável."}[trend]
        )
    return "\n".join(lines)


def muscles(t: Turn) -> Step:
    target = muscle_in(t.q)
    days = t.days()
    if not t.has("get_muscle_stimulus"):
        args: dict[str, Any] = t.period(days)
        if target:
            args["muscle_ids"] = [target]
        return [("get_muscle_stimulus", args)]
    data = t.last("get_muscle_stimulus")
    if "error" in data:
        return f"Não consegui consultar o estímulo: {data['error']}"
    rows = data.get("muscles") or []
    if not any(m.get("weighted_sets_per_week") for m in rows):
        return (
            f"Ainda não há registros de musculação nos últimos {data.get('period_days', days)} "
            "dias, então não há estímulo para mostrar."
        )
    if target:
        m = next((r for r in rows if r["muscle_id"] == target), None)
        if m is None:
            return "Não encontrei esse músculo no mapa."
        text = (
            f"**{m['name']}** nos últimos {data['period_days']} dias: "
            f"{plural(m['weighted_sets_per_week'], 'série', 'séries')} por semana, faixa "
            f"**{BANDS.get(m['band'], m['band'])}**"
        )
        days_on = m.get("frequency_days")
        text += f", em {plural(days_on, 'dia', 'dias')}." if days_on else "."
        if m["band"] in ("none", "low"):
            text += (
                "\n\nPara subir de faixa, vale incluir mais séries para esse músculo ao "
                "longo da semana — posso preparar uma proposta para a sua ficha."
            )
        return text + "\n\n" + NOTE_REFERENCE
    ordered = sorted(rows, key=lambda r: r["weighted_sets_per_week"])
    zero = [r["name"] for r in ordered if not r["weighted_sets_per_week"]]
    low = [r for r in ordered if r["weighted_sets_per_week"]][:3]
    lines = [f"Nos últimos {data['period_days']} dias:"]
    if zero:
        lines.append(f"- **Sem nenhuma série:** {', '.join(zero)}.")
    for r in low:
        lines.append(
            f"- **{r['name']}:** "
            f"{plural(r['weighted_sets_per_week'], 'série', 'séries')} por semana "
            f"(faixa {BANDS.get(r['band'], r['band'])})."
        )
    return "\n".join(lines) + "\n\n" + NOTE_REFERENCE


def goals(t: Turn) -> Step:
    if not t.has("get_goals"):
        return [("get_goals", {})]
    items = (t.last("get_goals") or {}).get("items") or []
    if not items:
        return (
            "Você ainda não tem metas ativas. Quer que eu prepare uma? Por exemplo: "
            '"Crie uma meta de correr 5 km".'
        )
    lines = ["Suas metas ativas:"]
    for g in items:
        p = g.get("progress")
        text = f"- **{g['title']}**"
        if not p or p.get("current") is None:
            text += f" ({g['target']}): ainda sem registro que meça essa meta."
        else:
            unit = p["unit"]
            if unit == "s":
                current = pace(int(p["current"])).removesuffix(" /km")
                goal = pace(int(p["target"])).removesuffix(" /km")
            else:
                current, goal = num(p["current"]), num(p["target"])
            unit_text = {"sets_per_week": "séries/semana", "sessions": "treinos", "s": ""}.get(
                unit, unit
            )
            ratio = p.get("ratio") or 0
            if p.get("achieved"):
                status = "alvo atingido!"
            elif ratio >= 0.75:
                status = "falta pouco."
            elif ratio >= 0.5:
                status = "mais da metade do caminho."
            else:
                status = "ainda no começo."
            text += f": {current} de {goal} {unit_text}".rstrip() + f" — {status}"
            if p.get("basis"):
                text += f" ({p['basis']})"
        lines.append(text)
    return "\n".join(lines)


def current_session(t: Turn) -> Step:
    if not t.has("get_current_session"):
        return [("get_current_session", {})]
    session = (t.last("get_current_session") or {}).get("session")
    if not session:
        return "Não há nenhum treino em andamento agora."
    state = "pausado" if session.get("status") == "paused" else "em andamento"
    return (
        f"Sim: **{session.get('name') or 'Treino'}** está {state}, há "
        f"{minutes(session.get('elapsed_s'))}, com "
        f"{plural(session.get('sets', 0), 'série', 'séries')} até agora."
    )


def _exercise_name(q: str) -> str | None:
    match = re.search(r"\b(?:no|na|do|da|de|em)\s+([a-z][a-z ]{1,60})$", q)
    return match.group(1).strip() if match else None


def one_rm(t: Turn) -> Step:
    name = _exercise_name(t.q)
    focused = t.focus.get("exercise")
    if name is None and focused is None:
        return 'Em qual exercício? Por exemplo: "Qual é o meu 1RM estimado no supino?"'
    if not t.has("get_exercise_history"):
        if focused:
            return [("get_exercise_history", {"exercise_id": focused})]
        return [
            ("get_exercise_history", {"name": name}),
            ("get_workout_history", {**t.period(366), "limit": 20}),
        ]
    data = t.last("get_exercise_history")
    if "error" in data:
        return f"Não encontrei esse exercício nos seus registros: {data['error']}"
    if data.get("ambiguous"):
        if len(t.results["get_exercise_history"]) > 1:
            return "Encontrei mais de um exercício com esse nome. Pode dizer o nome completo?"
        done = {
            name
            for item in (t.last("get_workout_history") or {}).get("items", [])
            for name in item.get("exercises", [])
        }
        candidates = data["candidates"]["items"]
        chosen = next((c for c in candidates if c["name"] in done), candidates[0])
        return [("get_exercise_history", {"exercise_id": chosen["exercise_id"]})]
    exercise = data["exercise"]["name"]
    trend = data.get("e1rm_trend") or {}
    last = trend.get("last")
    if not last:
        return (
            f"Ainda não há registros de **{exercise}** com carga e repetições para estimar o 1RM."
        )
    text = (
        f"Seu 1RM estimado no **{exercise}** é de cerca de **{num(last['kg'])} kg** "
        f"(treino de {day(last['date'])})."
    )
    first = trend.get("first")
    if first and first["date"] != last["date"]:
        text += f" No primeiro registro do período era {num(first['kg'])} kg."
    return text + (
        "\n\nÉ uma estimativa pela fórmula de Epley, a partir das suas séries — não um "
        "teste de carga máxima. Para testar de verdade, faça com acompanhamento."
    )


def search(t: Turn) -> Step:
    muscle = muscle_in(t.q)
    if not t.has("search_exercises"):
        args: dict[str, Any] = {"only_my_equipment": True}
        if muscle:
            args["muscle_id"] = muscle
        return [("search_exercises", args)]
    data = t.last("search_exercises")
    if "error" in data:
        return f"Não consegui buscar exercícios: {data['error']}"
    items = data.get("items") or []
    if muscle:
        primary = [
            e
            for e in items
            if any(m["muscle_id"] == muscle and m["role"] == "primary" for m in e["muscles"])
        ]
        items = primary or items
    items = items[:8]
    if not items:
        return "Não encontrei exercícios compatíveis com o seu equipamento para esse músculo."
    lines = ["Algumas opções:" if len(items) > 1 else "Uma opção:"]
    lines += [f"- **{e['name']}** ({e['equipment']})" for e in items]
    if data.get("equipment_filter"):
        lines.append("\nFiltrei pelo equipamento que está no seu perfil.")
    lines.append("Se quiser, posso propor um deles na sua ficha.")
    return "\n".join(lines)


def _template_for(q: str, templates: list[dict[str, Any]]) -> dict[str, Any]:
    named = [tp for tp in templates if normalize(tp["name"]) in q]
    return max(named, key=lambda tp: len(tp["name"])) if named else templates[0]


def propose_exercise(t: Turn) -> Step:
    muscle = muscle_in(t.q) or t.focus.get("muscle")
    if not t.has("get_templates"):
        calls: list[Call] = [("get_templates", {})]
        if muscle is None:
            calls.append(("get_muscle_stimulus", t.period(30)))
        return calls
    templates = (t.last("get_templates") or {}).get("items") or []
    if not templates:
        return (
            "Você ainda não tem fichas de treino. Crie uma em **Treinos → Fichas** e "
            "depois me peça a sugestão de novo."
        )
    if muscle is None:
        rows = (t.last("get_muscle_stimulus") or {}).get("muscles") or []
        rows = [r for r in rows if r["muscle_id"] not in ("forearms", "obliques", "traps")]
        weakest = min(rows, key=lambda r: r["weighted_sets_per_week"]) if rows else None
        muscle = weakest["muscle_id"] if weakest else "chest"
    if not t.has("search_exercises"):
        return [("search_exercises", {"muscle_id": muscle, "only_my_equipment": True})]
    template = _template_for(t.q, templates)
    if not t.has("prepare_change_proposal"):
        in_template = {i["exercise_id"] for i in template["items"]}
        options = [
            e
            for e in (t.last("search_exercises") or {}).get("items", [])
            if e["exercise_id"] not in in_template
            and any(m["muscle_id"] == muscle and m["role"] == "primary" for m in e["muscles"])
        ]
        if not options:
            return (
                f"Não encontrei um exercício novo compatível com o seu equipamento para "
                f"incluir na ficha **{template['name']}**."
            )
        exercise = options[0]
        change = {
            "kind": "template_add_exercise",
            "template_id": template["template_id"],
            "exercise_id": exercise["exercise_id"],
            "planned_sets": [{"reps_min": 8, "reps_max": 12, "rir_target": 2}] * 3,
            "rest_s": 90,
        }
        rationale = (
            f"Incluir {exercise['name']} para trabalhar mais esse músculo, com um "
            "exercício compatível com o seu equipamento."
        )
        return [("prepare_change_proposal", {"change": change, "rationale": rationale})]
    return _proposal_answer(t)


def _proposal_answer(t: Turn) -> str:
    result = t.last("prepare_change_proposal")
    if "error" in result:
        return f"Não consegui preparar a proposta: {result['error']}"
    details = "".join(f"\n- {d}" for d in result.get("details") or [])
    return (
        f"Preparei uma proposta: **{result['summary']}**.{details}\n\n"
        "Ela **ainda não foi aplicada**: confira o cartão abaixo e toque em **Confirmar** "
        "para mudar ou em **Recusar** para descartar."
    )


_GOAL_EXERCISE = re.compile(
    r"meta (?:de|no|na|para o|para a)\s+([^\d]+?)\s+(?:com|de|para|em)\s+\d"
)


def propose_goal(t: Turn) -> Step:
    if t.has("prepare_change_proposal"):
        return _proposal_answer(t)
    text = t.question.lower()
    load = re.search(r"(\d+(?:[.,]\d+)?)\s*kg", text)
    reps = re.search(r"(\d+)\s*(?:rep|x\b)", text)
    km = re.search(r"(\d+(?:[.,]\d+)?)\s*km", text)
    if load:
        match = _GOAL_EXERCISE.search(text)
        exercise = (match.group(1) if match else "").strip()
        if not exercise:
            return (
                'Para qual exercício? Por exemplo: "Crie uma meta de supino com 70 kg '
                'para 5 repetições".'
            )
        change: dict[str, Any] = {
            "kind": "goal_create",
            "goal_kind": "strength",
            "title": f"{exercise.capitalize()} {load.group(1)} kg",
            "target": {
                "exercise": exercise.capitalize(),
                "load_kg": float(load.group(1).replace(",", ".")),
                "reps": int(reps.group(1)) if reps else 1,
            },
        }
    elif km:
        distance = float(km.group(1).replace(",", "."))
        change = {
            "kind": "goal_create",
            "goal_kind": "run_distance",
            "title": f"Correr {km.group(1)} km",
            "target": {"distance_km": distance},
        }
    else:
        return (
            'Que meta você quer? Por exemplo: "Crie uma meta de supino com 70 kg para 5 '
            'repetições" ou "Crie uma meta de correr 10 km".'
        )
    return [
        (
            "prepare_change_proposal",
            {"change": change, "rationale": "Meta pedida por você no chat."},
        )
    ]


def history_overview(t: Turn) -> Step:
    """Pergunta sobre treinos sem intenção mais específica: o resumo do período."""
    days = t.days()
    if not t.has("get_workout_history"):
        return [
            ("get_workout_history", {**t.period(days), "limit": 10}),
            ("get_activities", {**t.period(days), "limit": 10}),
        ]
    items = t.last("get_workout_history").get("items") or []
    total = t.last("get_workout_history").get("total_sessions", len(items))
    runs = (t.last("get_activities") or {}).get("items") or []
    if not items and not runs:
        return f"Ainda não há registros nos últimos {days} dias."
    span = t.period(days)
    lines = [f"De {day(span['from_date'])} a {day(span['to_date'])}:"]
    if items:
        lines.append(f"\n**Musculação:** {plural(total, 'treino', 'treinos')}")
        lines += [
            f"- {day(i['started_at'])}, {i.get('name') or 'Treino'}: "
            f"{plural(i.get('sets') or 0, 'série válida', 'séries válidas')}"
            for i in items[:5]
        ]
    if runs:
        lines.append(f"\n**Atividades:** {len(runs)}")
        lines += [
            f"- {day(r['started_at'])}, {MODALITY_NAMES.get(r['modality'], r['modality'])}"
            + (f": {num(r['distance_m'] / 1000)} km" if r.get("distance_m") else "")
            for r in runs[:5]
        ]
    return "\n".join(lines)


# --- a escolha da intenção (a ordem importa) ---


_CHANGE_VERBS = ("adicion", "acrescent", "inclu", "coloc", "bot", "sugir", "propo")


def choose(t: Turn) -> Callable[[Turn], Step] | str:
    q = t.q
    other = re.search(r"\boutr[ao]s? (conta|pessoa|usuari)", q)
    if ("ignor" in q and "instru" in q) or "@" in q or other:
        return OTHER_ACCOUNT
    if re.search(r"\b(dor|dores|doi|doendo|lesao|lesionei|machuc|inflama|torci|estalo)", q):
        return PAIN
    if re.search(r"\b(dieta|kcal|caloria|jejum|secar|emagrecer rapido)", q):
        return DIET
    if re.search(r"\b(hormon|esteroide|anaboliz|testosterona|bomba)", q):
        return HORMONE
    if "meta" in q and has_word(q, "cri", "defin", "coloc", "adicion", "nova", "quero"):
        return propose_goal
    if "ficha" in q and has_word(q, *_CHANGE_VERBS):
        return propose_exercise
    # Conversa com foco (atalhos do Meu Corpo, do treino e do exercício).
    if "session" in t.focus:
        return session_focus
    if "muscle" in t.focus:
        return muscle_focus
    if "exercise" in t.focus:
        return one_rm
    if "exercicio" in q and has_word(q, "posso", "opc", "sugest", "sugir", "quais", "que", "indiq"):
        return search
    if has_word(q, "meta", "metas", "objetivo"):
        return goals
    if has_word(q, "andamento", "aberto", "agora", "pausado"):
        return current_session
    if has_word(q, "1rm", "rm", "maxim", "recorde"):
        return one_rm
    if has_word(q, "musculo", "estimulo", "grupo") or muscle_in(q):
        return muscles
    if (mod := modality_in(q)) or has_word(q, "pace", "ritmo"):
        chosen = mod or ("run", "corrida")
        return lambda turn: endurance(turn, chosen)
    if has_word(q, "compar", "anterior", "passad", "evolu", "progress"):
        return compare_weeks
    if re.search(r"\b(esta|essa|nesta|nessa|minha) semana\b", q):
        return week_totals
    if has_word(q, "ultim", "sessao", "fiz"):
        return last_session
    if has_word(q, "trein", "historic", "registr", "atividade"):
        return history_overview
    if has_word(q, "oi", "ola", "ajuda", "ajud", "bom", "boa") or not q:
        return HELP
    return OUT_OF_SCOPE


class DemoProvider:
    """Responde por regras, consultando as ferramentas de verdade (ver o módulo)."""

    name = "demo"
    model = DEMO_MODEL

    def complete(
        self,
        *,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int,
        timeout_s: float,
    ) -> Completion:
        turn = read_turn(system, copy.deepcopy(messages))
        intent = choose(turn)
        step = intent if isinstance(intent, str) else intent(turn)
        if isinstance(step, list) and not tools:
            # Sem ferramentas na rodada (limite atingido): responde com o que tem.
            step = "Não consegui consultar todos os dados desta vez. Tente perguntar de novo."
        prompt = estimate_tokens(system + "".join(m.content for m in messages))
        if isinstance(step, str):
            return Completion(
                text=step,
                stop_reason="end",
                usage=Usage(prompt, estimate_tokens(step)),
                model=DEMO_MODEL,
            )
        offset = len(turn.calls)
        calls = tuple(
            ToolCall(id=f"demo-{offset + i}", name=name, arguments=args)
            for i, (name, args) in enumerate(step)
        )
        return Completion(
            text="",
            tool_calls=calls,
            stop_reason="tool_use",
            usage=Usage(prompt, estimate_tokens(json.dumps([c.arguments for c in calls]))),
            model=DEMO_MODEL,
        )
