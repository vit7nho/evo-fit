"""Vocabulários das fichas, com rótulos em PT-BR (expostos em GET /workout-options)."""

from typing import Final

# Agrupamentos entre exercícios (ADR-009) e quantos exercícios cada um aceita.
GROUP_KINDS: Final = {
    "biset": "Bi-set",
    "superset": "Supersérie",
    "triset": "Tri-set",
    "giant_set": "Série gigante",
}
GROUP_SIZES: Final = {
    "biset": (2, 2),
    "superset": (2, 2),
    "triset": (3, 3),
    "giant_set": (4, 6),
}

# Tipo de cada série planejada. No plano, drop e rest-pause marcam a série em que aplicar a
# técnica; na execução (2.7), ela é registrada como válida e os segmentos vêm encadeados.
SET_KINDS: Final = {
    "warmup": "Aquecimento",
    "working": "Válida",
    "drop": "Drop set",
    "rest_pause": "Rest-pause",
}

MAX_TEMPLATES = 50
MAX_ITEMS = 30
MAX_SETS = 10
