"""Fichas de treino do usuário autenticado (docs/DATA_MODEL.md §3, ADR-009).

A ficha é salva inteira (nome, itens na ordem e grupos): o editor monta tudo e envia
num pedido só, então não existe estado pela metade. A ficha de outra pessoa responde
404; os exercícios usados precisam estar visíveis para o dono (catálogo ou próprios).
"""

import logging
import uuid
from collections.abc import Sequence

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.modules.exercises.models import Exercise
from app.modules.training import catalog
from app.modules.training.models import ExerciseGroup, TemplateItem, WorkoutTemplate
from app.modules.training.schemas import ItemIn, TemplateIn
from app.modules.users.models import User

logger = logging.getLogger(__name__)


class TemplateLimitError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "template_limit",
            "Limite de fichas",
            f"Você já tem {catalog.MAX_TEMPLATES} fichas. Exclua alguma antes de criar outra.",
        )


def _check_groups(data: TemplateIn) -> None:
    """Cada grupo usado existe, tem membros consecutivos e o tamanho certo para o tipo."""
    members: dict[int, list[int]] = {}
    for index, item in enumerate(data.items):
        if item.group is not None:
            if item.group >= len(data.groups):
                raise FieldValidationError(f"items.{index}.group", "Grupo inexistente.")
            members.setdefault(item.group, []).append(index)
    for group_index, group in enumerate(data.groups):
        positions = members.get(group_index, [])
        if not positions:
            raise FieldValidationError(f"groups.{group_index}", "Grupo sem exercícios.")
        if positions != list(range(positions[0], positions[0] + len(positions))):
            raise FieldValidationError(
                f"groups.{group_index}", "Os exercícios de um grupo precisam ficar em sequência."
            )
        low, high = catalog.GROUP_SIZES[group.kind]
        if not low <= len(positions) <= high:
            label = catalog.GROUP_KINDS[group.kind]
            size = f"{low}" if low == high else f"de {low} a {high}"
            raise FieldValidationError(f"groups.{group_index}", f"{label} tem {size} exercícios.")


def _check_sets(index: int, item: ItemIn, exercise: Exercise) -> None:
    """Exercício por tempo planeja duração; os demais, repetições."""
    timed = exercise.load_type == "time"
    for set_index, planned in enumerate(item.planned_sets):
        if timed and planned.duration_s is None:
            raise FieldValidationError(
                f"items.{index}.planned_sets.{set_index}",
                f"{exercise.name} é feito por tempo: informe a duração.",
            )
        if not timed and planned.duration_s is not None:
            raise FieldValidationError(
                f"items.{index}.planned_sets.{set_index}",
                f"{exercise.name} é feito por repetições.",
            )


class TemplateService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list(self, user: User) -> list[WorkoutTemplate]:
        return list(
            self.db.scalars(
                select(WorkoutTemplate)
                .where(WorkoutTemplate.user_id == user.id)
                .order_by(WorkoutTemplate.position, WorkoutTemplate.created_at)
            )
        )

    def get(self, user: User, template_id: uuid.UUID) -> WorkoutTemplate:
        template = self.db.scalar(
            select(WorkoutTemplate).where(
                WorkoutTemplate.id == template_id, WorkoutTemplate.user_id == user.id
            )
        )
        if template is None:
            raise NotFoundError("Ficha não encontrada.")
        return template

    def create(self, user: User, data: TemplateIn) -> WorkoutTemplate:
        count = self.db.scalar(
            select(func.count())
            .select_from(WorkoutTemplate)
            .where(WorkoutTemplate.user_id == user.id)
        )
        if (count or 0) >= catalog.MAX_TEMPLATES:
            raise TemplateLimitError
        last = self.db.scalar(
            select(func.max(WorkoutTemplate.position)).where(WorkoutTemplate.user_id == user.id)
        )
        template = WorkoutTemplate(user_id=user.id, position=(last or 0) + 1, name="")
        self._fill(user, template, data)
        self.db.add(template)
        self.db.commit()
        self.db.refresh(template)
        logger.info(
            "template_created",
            extra={"user_id": str(user.id), "template_id": str(template.id)},
        )
        return template

    def replace(self, user: User, template_id: uuid.UUID, data: TemplateIn) -> WorkoutTemplate:
        template = self.get(user, template_id)
        # Esvazia antes de regravar: as posições (únicas por ficha) se repetem.
        template.items.clear()
        template.groups.clear()
        self.db.flush()
        self._fill(user, template, data)
        self.db.commit()
        self.db.refresh(template)
        logger.info(
            "template_updated",
            extra={"user_id": str(user.id), "template_id": str(template.id)},
        )
        return template

    def delete(self, user: User, template_id: uuid.UUID) -> None:
        template = self.get(user, template_id)
        self.db.delete(template)
        self.db.commit()
        logger.info(
            "template_deleted", extra={"user_id": str(user.id), "template_id": str(template_id)}
        )

    def reorder(self, user: User, template_ids: Sequence[uuid.UUID]) -> list[WorkoutTemplate]:
        templates = {t.id: t for t in self.list(user)}
        if len(template_ids) != len(set(template_ids)) or set(template_ids) != set(templates):
            raise FieldValidationError(
                "template_ids", "Envie todas as suas fichas, cada uma uma vez."
            )
        for position, template_id in enumerate(template_ids, start=1):
            templates[template_id].position = position
        self.db.commit()
        return self.list(user)

    def _fill(self, user: User, template: WorkoutTemplate, data: TemplateIn) -> None:
        _check_groups(data)
        exercises = self._visible_exercises(user, {item.exercise_id for item in data.items})
        for index, item in enumerate(data.items):
            exercise = exercises.get(item.exercise_id)
            if exercise is None:
                raise FieldValidationError(
                    f"items.{index}.exercise_id", "Exercício não encontrado."
                )
            _check_sets(index, item, exercise)

        template.name = data.name
        template.notes = data.notes or None
        groups = [
            ExerciseGroup(position=i, kind=g.kind, rest_after_s=g.rest_after_s)
            for i, g in enumerate(data.groups)
        ]
        template.groups.extend(groups)
        template.items.extend(
            TemplateItem(
                exercise_id=item.exercise_id,
                position=index,
                group=None if item.group is None else groups[item.group],
                planned_sets=[s.model_dump(exclude_none=True) for s in item.planned_sets],
                rest_s=item.rest_s,
                notes=item.notes or None,
            )
            for index, item in enumerate(data.items)
        )

    def _visible_exercises(self, user: User, ids: set[uuid.UUID]) -> dict[uuid.UUID, Exercise]:
        if not ids:
            return {}
        rows = self.db.scalars(
            select(Exercise).where(
                Exercise.id.in_(ids),
                or_(Exercise.owner_user_id.is_(None), Exercise.owner_user_id == user.id),
            )
        )
        return {e.id: e for e in rows}
