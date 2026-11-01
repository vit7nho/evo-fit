"""Tipos de meta e os campos do alvo (`target`) de cada um.

Fonte única: a API valida o alvo por estas definições e as expõe em
GET /goal-options, de onde o app monta o formulário de cada tipo. Um tipo novo
aparece no app sem atualizá-lo. Unidades fixas no sistema métrico (kg, km, s).
"""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Final, Literal

from app.core.errors import FieldValidationError
from app.modules.exercises import catalog
from app.modules.users import vocabulary

FieldType = Literal["text", "int", "number", "choice", "duration"]

# Fonte única dos grupos musculares: o catálogo de exercícios (tabela muscle_groups).
MUSCLE_GROUPS: Final = catalog.MUSCLE_NAMES


@dataclass(frozen=True)
class TargetField:
    """Um campo do alvo. Em `text`, `min`/`max` são o tamanho; em `duration`, segundos."""

    key: str
    label: str
    type: FieldType
    required: bool = True
    min: float | None = None
    max: float | None = None
    step: float | None = None
    unit: str | None = None
    options: Mapping[str, str] | None = None


@dataclass(frozen=True)
class GoalKind:
    code: str
    label: str
    description: str
    fields: tuple[TargetField, ...]
    # Peso corporal é dado de saúde (docs/SECURITY_PRIVACY.md §1): exige health_data.
    health_data: bool = False


_WEIGHT = TargetField(
    "target_weight_kg", "Peso desejado", "number", min=30, max=300, step=0.1, unit="kg"
)
_DISTANCE = TargetField("distance_km", "Distância", "number", min=0.1, max=100, step=0.1, unit="km")

KINDS: Final[dict[str, GoalKind]] = {
    kind.code: kind
    for kind in (
        GoalKind(
            "strength",
            "Força",
            "Levantar uma carga num exercício.",
            (
                TargetField("exercise", "Exercício", "text", min=2, max=80),
                TargetField("load_kg", "Carga", "number", min=1, max=500, step=0.5, unit="kg"),
                TargetField("reps", "Repetições", "int", min=1, max=30),
            ),
        ),
        GoalKind(
            "hypertrophy",
            "Hipertrofia",
            "Treinar um grupo muscular com um volume semanal.",
            (
                TargetField("muscle_group", "Grupo muscular", "choice", options=MUSCLE_GROUPS),
                TargetField("weekly_sets", "Séries por semana", "int", min=1, max=40),
            ),
        ),
        GoalKind(
            "weight_loss",
            "Perder peso",
            "Chegar a um peso menor.",
            (_WEIGHT,),
            health_data=True,
        ),
        GoalKind(
            "weight_gain",
            "Ganhar peso",
            "Chegar a um peso maior.",
            (_WEIGHT,),
            health_data=True,
        ),
        GoalKind(
            "weight_maintenance",
            "Manter o peso",
            "Ficar perto de um peso, com uma margem.",
            (
                _WEIGHT,
                TargetField(
                    "tolerance_kg", "Margem", "number", min=0.5, max=5, step=0.5, unit="kg"
                ),
            ),
            health_data=True,
        ),
        GoalKind(
            "run_distance",
            "Distância de corrida",
            "Conseguir correr uma distância.",
            (_DISTANCE,),
        ),
        GoalKind(
            "run_time",
            "Tempo de corrida",
            "Correr uma distância em até um tempo.",
            (_DISTANCE, TargetField("time_s", "Tempo", "duration", min=60, max=86_400)),
        ),
        GoalKind(
            "frequency",
            "Frequência",
            "Treinar um número de vezes por semana.",
            (
                TargetField("sessions_per_week", "Treinos por semana", "int", min=1, max=14),
                TargetField(
                    "modality",
                    "Modalidade",
                    "choice",
                    required=False,
                    options=vocabulary.MODALITIES,
                ),
            ),
        ),
        GoalKind(
            "habit",
            "Hábito",
            "Repetir algo alguns dias por semana.",
            (
                TargetField("description", "O hábito", "text", min=2, max=120),
                TargetField("days_per_week", "Dias por semana", "int", min=1, max=7),
            ),
        ),
        GoalKind(
            "custom",
            "Personalizada",
            "Qualquer outra meta, descrita com suas palavras.",
            (TargetField("description", "Detalhes", "text", required=False, min=0, max=500),),
        ),
    )
}

HEALTH_KINDS: Final = frozenset(code for code, kind in KINDS.items() if kind.health_data)


def get_kind(code: str) -> GoalKind:
    kind = KINDS.get(code)
    if kind is None:
        raise FieldValidationError("kind", "Tipo de meta inválido.")
    return kind


def _decimals(step: float) -> int:
    text = f"{step:g}"
    return len(text.split(".")[1]) if "." in text else 0


def _number(spec: TargetField, raw: Any, path: str) -> float | int:
    is_number = isinstance(raw, int | float) and not isinstance(raw, bool)
    if spec.type == "int" or spec.type == "duration":
        if not is_number or raw != int(raw):
            raise FieldValidationError(path, "Informe um número inteiro.")
        value: float | int = int(raw)
    else:
        if not is_number:
            raise FieldValidationError(path, "Informe um número.")
        value = float(raw)
        if spec.step is not None:
            places = _decimals(spec.step)
            rounded = round(value / spec.step) * spec.step
            if abs(rounded - value) > 1e-9:
                raise FieldValidationError(path, f"Use múltiplos de {format_number(spec.step)}.")
            value = round(rounded, places)
    too_low = spec.min is not None and value < spec.min
    too_high = spec.max is not None and value > spec.max
    if too_low or too_high:
        low, high = format_number(spec.min or 0), format_number(spec.max or 0)
        unit = f" {spec.unit}" if spec.unit else ""
        raise FieldValidationError(path, f"Informe um valor entre {low} e {high}{unit}.")
    return value


def validate_target(kind: GoalKind, target: Mapping[str, Any]) -> dict[str, Any]:
    """Confere o alvo contra os campos do tipo e devolve a versão normalizada."""
    fields = {f.key: f for f in kind.fields}
    for key in target:
        if key not in fields:
            message = "Campo desconhecido para este tipo de meta."
            raise FieldValidationError(f"target.{key}", message)

    clean: dict[str, Any] = {}
    for spec in kind.fields:
        path = f"target.{spec.key}"
        raw = target.get(spec.key)
        if isinstance(raw, str):
            raw = raw.strip()
        if raw is None or raw == "":
            if spec.required:
                raise FieldValidationError(path, "Campo obrigatório.")
            continue

        if spec.type == "text":
            if not isinstance(raw, str):
                raise FieldValidationError(path, "Informe um texto.")
            if not (spec.min or 0) <= len(raw) <= (spec.max or 0):
                raise FieldValidationError(
                    path, f"Use de {int(spec.min or 0)} a {int(spec.max or 0)} caracteres."
                )
            clean[spec.key] = raw
        elif spec.type == "choice":
            if raw not in (spec.options or {}):
                raise FieldValidationError(path, "Escolha uma das opções.")
            clean[spec.key] = raw
        else:
            clean[spec.key] = _number(spec, raw, path)
    return clean


# --- resumo legível do alvo (ex.: "Supino: 80 kg x 5", com o sinal de vezes) ---


def format_number(value: float) -> str:
    """Número no formato brasileiro, sem casas decimais desnecessárias."""
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return text.replace(".", ",")


def format_duration(seconds: int) -> str:
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def summarize(kind_code: str, target: Mapping[str, Any]) -> str:
    t = target
    match kind_code:
        case "strength":
            # Sinal de multiplicação de propósito (tipografia), não a letra x.
            return f"{t['exercise']}: {format_number(t['load_kg'])} kg × {t['reps']}"  # noqa: RUF001
        case "hypertrophy":
            muscle = MUSCLE_GROUPS[t["muscle_group"]]
            return f"{muscle}: {t['weekly_sets']} séries por semana"
        case "weight_loss" | "weight_gain":
            return f"{format_number(t['target_weight_kg'])} kg"
        case "weight_maintenance":
            weight, margin = t["target_weight_kg"], t["tolerance_kg"]
            return f"{format_number(weight)} kg ± {format_number(margin)} kg"
        case "run_distance":
            return f"{format_number(t['distance_km'])} km"
        case "run_time":
            return f"{format_number(t['distance_km'])} km em {format_duration(t['time_s'])}"
        case "frequency":
            text = f"{t['sessions_per_week']}x por semana"
            modality = t.get("modality")
            return f"{text} · {vocabulary.MODALITIES[modality]}" if modality else text
        case "habit":
            return f"{t['description']} · {t['days_per_week']}x por semana"
        case _:
            return t.get("description", "")
