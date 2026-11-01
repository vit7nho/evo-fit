"""Carga do catálogo global (grupos musculares e exercícios do projeto, ADR-016).

Usado pelas migrações: o catálogo chega junto com o esquema, em qualquer ambiente.
Os ids dos exercícios globais são derivados do slug (UUID v5), então são os mesmos
em todas as máquinas e uma nova versão do seed atualiza em vez de duplicar.
"""

import json
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Any

import sqlalchemy as sa
from sqlalchemy.engine import Connection

from app.modules.exercises import catalog

SEED_DIR = Path(__file__).parent
IMAGES_DIR = SEED_DIR / "images"
# Caminho público das fotos do catálogo (montado em app/main.py).
IMAGES_URL = "/api/v1/media/exercises"
_NAMESPACE = uuid.UUID("5b0f8a8e-3c1d-4f3a-9a52-0e6f1e2b7c11")


def global_exercise_id(slug: str) -> uuid.UUID:
    return uuid.uuid5(_NAMESPACE, f"exercise:{slug}")


@lru_cache
def _image_slugs() -> frozenset[str]:
    mapping = json.loads((SEED_DIR / "images.v1.json").read_text(encoding="utf-8"))["images"]
    return frozenset(slug for slug in mapping if (IMAGES_DIR / slug / "0.jpg").is_file())


def catalog_images(slug: str) -> list[str]:
    """Fotos (início e fim) de um exercício do catálogo; vazio se ele não tem."""
    if slug not in _image_slugs():
        return []
    return [f"{IMAGES_URL}/{slug}/0.jpg", f"{IMAGES_URL}/{slug}/1.jpg"]


def load_seed(version: str = "v1") -> list[dict[str, Any]]:
    data = json.loads((SEED_DIR / f"exercises.{version}.json").read_text(encoding="utf-8"))
    if data["version"] != version:
        raise ValueError(f"Seed {version} declara a versão {data['version']}.")
    return data["exercises"]


_muscle_groups = sa.table(
    "muscle_groups",
    sa.column("id"),
    sa.column("name_pt"),
    sa.column("body_region"),
    sa.column("view"),
    sa.column("position"),
)
_exercises = sa.table(
    "exercises",
    sa.column("id"),
    sa.column("owner_user_id"),
    sa.column("name"),
    sa.column("slug"),
    sa.column("search_name"),
    sa.column("instructions"),
    sa.column("mechanics"),
    sa.column("equipment"),
    sa.column("load_type"),
    sa.column("unilateral"),
    sa.column("is_active"),
)
_exercise_muscles = sa.table(
    "exercise_muscles",
    sa.column("exercise_id"),
    sa.column("muscle_group_id"),
    sa.column("role"),
)


def seed_muscle_groups(conn: Connection) -> None:
    conn.execute(
        _muscle_groups.insert(),
        [
            {
                "id": m.id,
                "name_pt": m.name,
                "body_region": m.body_region,
                "view": m.view,
                "position": i,
            }
            for i, m in enumerate(catalog.MUSCLE_GROUPS)
        ],
    )


def seed_exercises(conn: Connection, version: str = "v1") -> int:
    """Insere o catálogo global. Espera as tabelas vazias de exercícios globais."""
    rows, muscles = [], []
    for item in load_seed(version):
        exercise_id = global_exercise_id(item["slug"])
        rows.append(
            {
                "id": exercise_id,
                "owner_user_id": None,
                "name": item["name"],
                "slug": item["slug"],
                "search_name": catalog.search_key(item["name"]),
                "instructions": item["instructions"],
                "mechanics": item["mechanics"],
                "equipment": item["equipment"],
                "load_type": item["load_type"],
                "unilateral": item["unilateral"],
                "is_active": True,
            }
        )
        for role in ("primary", "secondary"):
            muscles.extend(
                {"exercise_id": exercise_id, "muscle_group_id": m, "role": role} for m in item[role]
            )
    conn.execute(_exercises.insert(), rows)
    conn.execute(_exercise_muscles.insert(), muscles)
    return len(rows)
