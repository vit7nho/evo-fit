"""Metas do usuário autenticado (docs/DATA_MODEL.md §2).

Toda consulta filtra pelo dono vindo do token: a meta de outra pessoa responde 404,
igual a uma que não existe, para não revelar que ela existe.
"""

import logging
import uuid
import zoneinfo
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.modules.goals import kinds
from app.modules.goals.models import Goal, GoalStatus
from app.modules.goals.schemas import GoalCreate, GoalUpdate
from app.modules.users.models import ConsentKind, User
from app.modules.users.service import ConsentRequiredError, active_consent

logger = logging.getLogger(__name__)

# Limite de metas ativas ao mesmo tempo: foco para o usuário e teto contra abuso.
MAX_ACTIVE = 30
# Janelas aceitas para as datas, a partir de hoje.
_START_PAST = timedelta(days=5 * 365)
_START_FUTURE = timedelta(days=365)
_TARGET_SPAN = timedelta(days=10 * 365)


class GoalLimitError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "goal_limit",
            "Limite de metas ativas",
            f"Você já tem {MAX_ACTIVE} metas ativas. Conclua ou abandone alguma antes.",
        )


def _today(user: User) -> date:
    """Hoje no fuso do usuário: perto da meia-noite, o dia em UTC pode ser outro."""
    tz = zoneinfo.ZoneInfo(user.profile.timezone if user.profile else "America/Sao_Paulo")
    return datetime.now(tz).date()


class GoalService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list(self, user: User, status: GoalStatus | None = None) -> list[Goal]:
        query = select(Goal).where(Goal.user_id == user.id)
        if status is not None:
            query = query.where(Goal.status == status)
        # Ativas primeiro; dentro delas, prioridade e prazo mais próximo.
        active_first = case((Goal.status == GoalStatus.ACTIVE, 0), else_=1)
        query = query.order_by(
            active_first,
            Goal.priority,
            Goal.target_date.asc().nulls_last(),
            Goal.created_at.desc(),
        )
        return list(self.db.scalars(query))

    def get(self, user: User, goal_id: uuid.UUID) -> Goal:
        goal = self.db.scalar(select(Goal).where(Goal.id == goal_id, Goal.user_id == user.id))
        if goal is None:
            raise NotFoundError("Meta não encontrada.")
        return goal

    def create(self, user: User, data: GoalCreate) -> Goal:
        kind = kinds.get_kind(data.kind)
        target = kinds.validate_target(kind, data.target)
        self._require_consent(user, kind)

        today = _today(user)
        start = data.start_date or today
        self._check_start(start, today)
        if data.target_date is not None and data.target_date < today:
            raise FieldValidationError("target_date", "O prazo não pode estar no passado.")
        self._check_target_date(start, data.target_date)
        self._check_limit(user)

        goal = Goal(
            user_id=user.id,
            kind=kind.code,
            title=data.title,
            target=target,
            start_date=start,
            target_date=data.target_date,
            priority=data.priority,
            status=GoalStatus.ACTIVE,
        )
        self.db.add(goal)
        self.db.commit()
        self.db.refresh(goal)
        # Sem título nem alvo no log: são texto livre e podem ser dados de saúde.
        logger.info(
            "goal_created",
            extra={"user_id": str(user.id), "goal_id": str(goal.id), "kind": goal.kind},
        )
        return goal

    def update(self, user: User, goal_id: uuid.UUID, data: GoalUpdate) -> Goal:
        goal = self.get(user, goal_id)
        changes = data.model_fields_set

        for name in {"title", "start_date", "status", "priority"} & changes:
            if getattr(data, name) is None:
                raise FieldValidationError(name, "Campo obrigatório.")

        if "target" in changes:
            if data.target is None:
                raise FieldValidationError("target", "Campo obrigatório.")
            kind = kinds.get_kind(goal.kind)
            self._require_consent(user, kind)
            goal.target = kinds.validate_target(kind, data.target)

        start = data.start_date if "start_date" in changes else goal.start_date
        target_date = data.target_date if "target_date" in changes else goal.target_date
        if "start_date" in changes and start is not None:
            self._check_start(start, _today(user))
        if start is not None:
            self._check_target_date(start, target_date)
            goal.start_date = start
        goal.target_date = target_date

        if data.title is not None:
            goal.title = data.title
        if data.priority is not None:
            goal.priority = data.priority
        if data.status is not None and data.status != goal.status:
            if data.status is GoalStatus.ACTIVE:
                self._check_limit(user)
                goal.closed_at = None
            else:
                goal.closed_at = datetime.now(UTC)
            goal.status = data.status

        self.db.commit()
        self.db.refresh(goal)
        logger.info(
            "goal_updated",
            extra={"user_id": str(user.id), "goal_id": str(goal.id), "fields": sorted(changes)},
        )
        return goal

    def delete(self, user: User, goal_id: uuid.UUID) -> None:
        goal = self.get(user, goal_id)
        self.db.delete(goal)
        self.db.commit()
        logger.info("goal_deleted", extra={"user_id": str(user.id), "goal_id": str(goal_id)})

    # --- regras ---

    def _require_consent(self, user: User, kind: kinds.GoalKind) -> None:
        if kind.health_data and not active_consent(self.db, user.id, ConsentKind.HEALTH_DATA):
            raise ConsentRequiredError(ConsentKind.HEALTH_DATA)

    def _check_limit(self, user: User) -> None:
        active = self.db.scalar(
            select(func.count())
            .select_from(Goal)
            .where(Goal.user_id == user.id, Goal.status == GoalStatus.ACTIVE)
        )
        if (active or 0) >= MAX_ACTIVE:
            raise GoalLimitError

    @staticmethod
    def _check_start(start: date, today: date) -> None:
        if not today - _START_PAST <= start <= today + _START_FUTURE:
            raise FieldValidationError(
                "start_date", "Use uma data de início entre 5 anos atrás e 1 ano à frente."
            )

    @staticmethod
    def _check_target_date(start: date, target_date: date | None) -> None:
        if target_date is None:
            return
        if target_date < start:
            raise FieldValidationError("target_date", "O prazo precisa ser depois do início.")
        if target_date > start + _TARGET_SPAN:
            raise FieldValidationError("target_date", "Use um prazo de até 10 anos.")
