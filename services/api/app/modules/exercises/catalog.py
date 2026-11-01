"""Vocabulários da biblioteca de exercícios, com rótulos em PT-BR.

Os grupos musculares também viram a tabela `muscle_groups` (migração 0004): o id é
estável e é o que o Meu Corpo vai usar para pintar cada região (ADR-010).
A ordem dos itens é a ordem de exibição.
"""

import unicodedata
from dataclasses import dataclass
from typing import Final


@dataclass(frozen=True)
class MuscleGroup:
    id: str
    name: str
    body_region: str  # upper | core | lower
    view: str  # front | back | both


MUSCLE_GROUPS: Final[tuple[MuscleGroup, ...]] = (
    MuscleGroup("chest", "Peito", "upper", "front"),
    MuscleGroup("delts", "Ombros", "upper", "both"),
    MuscleGroup("biceps", "Bíceps", "upper", "front"),
    MuscleGroup("triceps", "Tríceps", "upper", "back"),
    MuscleGroup("forearms", "Antebraços", "upper", "both"),
    MuscleGroup("lats", "Dorsais", "upper", "back"),
    MuscleGroup("traps", "Trapézio", "upper", "back"),
    MuscleGroup("abs", "Abdômen", "core", "front"),
    MuscleGroup("obliques", "Oblíquos", "core", "front"),
    MuscleGroup("glutes", "Glúteos", "lower", "back"),
    MuscleGroup("quads", "Quadríceps", "lower", "front"),
    MuscleGroup("hamstrings", "Posteriores de coxa", "lower", "back"),
    MuscleGroup("calves", "Panturrilhas", "lower", "back"),
)
MUSCLE_NAMES: Final = {m.id: m.name for m in MUSCLE_GROUPS}

# Códigos iguais aos do perfil (users/vocabulary.EQUIPMENT) quando o significado é o
# mesmo, para cruzar "exercícios que você consegue fazer" com o que a pessoa tem.
EQUIPMENT: Final = {
    "barbell": "Barra e anilhas",
    "dumbbells": "Halteres",
    "machine": "Máquina",
    "cable": "Polia",
    "kettlebell": "Kettlebell",
    "bands": "Elásticos",
    "pull_up_bar": "Barra fixa",
    # "Sem equipamento" e não "Peso do corpo": este é também o rótulo de LOAD_TYPES.
    "bodyweight": "Sem equipamento",
}

MECHANICS: Final = {"compound": "Multiarticular", "isolation": "Isolado"}

# Define se o volume (carga vezes repetições) faz sentido para o exercício.
LOAD_TYPES: Final = {
    "external": "Carga externa",
    "bodyweight": "Peso do corpo",
    "assisted": "Assistido",
    "time": "Por tempo",
}

MUSCLE_ROLES: Final = {"primary": "Principal", "secondary": "Secundário"}


def search_key(text: str) -> str:
    """Texto sem acentos, em minúsculas e com espaços simples: base da busca."""
    decomposed = unicodedata.normalize("NFKD", text)
    plain = "".join(c for c in decomposed if not unicodedata.combining(c))
    return " ".join(plain.lower().split())


def slugify(text: str) -> str:
    return "-".join("".join(c if c.isalnum() else " " for c in search_key(text)).split())
