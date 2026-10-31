"""Vocabulários controlados do perfil, com rótulos em PT-BR.

Fonte única: a API valida os valores por estes dicionários e os expõe em
GET /profile-options, de onde o app tira as opções e os rótulos que exibe.
A ordem dos itens é a ordem de exibição.
"""

from typing import Final

OBJECTIVES: Final = {
    "gain_muscle": "Ganhar massa muscular",
    "lose_weight": "Emagrecer",
    "maintain": "Manter a forma",
    "run": "Correr melhor",
    "walk_habit": "Criar o hábito de caminhar",
    "general_health": "Saúde geral",
}

MODALITIES: Final = {
    "strength": "Musculação",
    "run": "Corrida",
    "walk": "Caminhada",
    "cycle": "Ciclismo",
    "swim": "Natação",
    "functional": "Funcional",
}

EQUIPMENT: Final = {
    "gym": "Academia completa",
    "dumbbells": "Halteres",
    "barbell": "Barra e anilhas",
    "kettlebell": "Kettlebell",
    "bands": "Elásticos",
    "pull_up_bar": "Barra fixa",
    "bodyweight": "Só o peso do corpo",
    "treadmill": "Esteira",
    "bike": "Bicicleta",
    "pool": "Piscina",
}

DIETARY_PREFERENCES: Final = {
    "vegetarian": "Vegetariana",
    "vegan": "Vegana",
    "lactose_free": "Sem lactose",
    "gluten_free": "Sem glúten",
}

# Dado sensível de saúde (LGPD art. 11): só com o consentimento health_data ativo.
LIMITATION_TAGS: Final = {
    "knee": "Joelho",
    "lower_back": "Lombar",
    "shoulder": "Ombro",
    "neck": "Pescoço",
    "wrist": "Punho",
    "hip": "Quadril",
    "ankle": "Tornozelo",
    "cardiac_condition_reported": "Condição cardíaca",
    "hypertension_reported": "Pressão alta",
}

EXPERIENCE_LEVELS: Final = {
    "beginner": "Iniciante",
    "intermediate": "Intermediário",
    "advanced": "Avançado",
}

UNIT_SYSTEMS: Final = {
    "metric": "Métrico (kg, km)",
    "imperial": "Imperial (lb, mi)",
}

SEX_FOR_CALCULATIONS: Final = {
    "female": "Feminino",
    "male": "Masculino",
    "unspecified": "Prefiro não informar",
}
