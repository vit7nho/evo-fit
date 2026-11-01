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

# Tipo de cada série planejada. Na execução (2.6), drop e rest-pause viram segmentos
# encadeados à série principal; no plano, marcam onde aplicar a técnica.
SET_KINDS: Final = {
    "warmup": "Aquecimento",
    "working": "Válida",
    "drop": "Drop set",
    "rest_pause": "Rest-pause",
}

MAX_TEMPLATES = 50
MAX_ITEMS = 30
MAX_SETS = 10
