"""Planos progressivos do usuário autenticado (caminhada, 5 km, 10 km).

O plano é gerado de um template determinístico (templates.py) com poucas regras
explicáveis: semanas repetidas para quem informou limitação em joelho, quadril,
tornozelo ou lombar (só com o consentimento de saúde ativo) e um aviso para conversar
com o médico em caso de condição cardíaca ou pressão alta. Toda consulta filtra pelo
dono vindo do token: o plano de outra pessoa responde 404, igual a um que não existe.
"""

import logging
import uuid
import zoneinfo
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.errors import AppError, FieldValidationError, NotFoundError
from app.modules.activities.models import Activity, EnduranceDetails
from app.modules.plans.models import PlanSession, TrainingPlan
from app.modules.plans.schemas import PlanCreate
from app.modules.plans.templates import TEMPLATES, PlanTemplate, Week
from app.modules.users.models import ConsentKind, User
from app.modules.users.service import active_consent

logger = logging.getLogger(__name__)

JOINT_TAGS = {"knee", "hip", "ankle", "lower_back"}
CARDIO_TAGS = {"cardiac_condition_reported", "hypertension_reported"}
ADAPTATION_TEXTS = {
    "joint_care": (
        "Algumas semanas se repetem, para o corpo se adaptar com calma à corrida, "
        "por causa da limitação que você informou."
    ),
    "medical_clearance_advised": (
        "Você informou uma condição cardíaca ou pressão alta: converse com seu médico "
        "antes de começar e mantenha um ritmo em que consiga conversar."
    ),
}
TEN_K_NOTE = (
    "Para o 10 km, o ideal é já correr 5 km sem parar. Se ainda não corre, comece pelo "
    "plano “Primeiros 5 km”."
)
SESSIONS_PER_WEEK = 3
_START_AHEAD = timedelta(days=28)
# Uma corrida de 5 km registrada nesse período indica base para o 10 km. Só a duração
# não basta: as sessões do próprio plano de 5 km têm 30 minutos com caminhada no meio.
_RECENT = timedelta(days=120)
_COUNTS_FOR = {"walk": {"walk", "run"}, "run": {"run"}}


class PlanInProgressError(AppError):
    def __init__(self, plan_id: uuid.UUID) -> None:
        super().__init__(
            409,
            "plan_in_progress",
            "Plano em andamento",
            "Você já tem um plano em andamento. Encerre-o antes de começar outro.",
            errors=[{"field": "plan_id", "message": str(plan_id)}],
        )


class PlanClosedError(AppError):
    def __init__(self) -> None:
        super().__init__(409, "plan_closed", "Plano encerrado", "Este plano já foi encerrado.")


def _now() -> datetime:
    return datetime.now(UTC)


def _tz(user: User) -> zoneinfo.ZoneInfo:
    return zoneinfo.ZoneInfo(user.profile.timezone if user.profile else "America/Sao_Paulo")


def _today(user: User) -> date:
    """Hoje no fuso do usuário: perto da meia-noite, o dia em UTC pode ser outro."""
    return datetime.now(_tz(user)).date()


def expanded_weeks(template: PlanTemplate, joint_care: bool) -> list[tuple[int, Week]]:
    """(semana do template, sessões). Com `joint_care`, as semanas pares se repetem
    (exceto a última), dando mais tempo de adaptação antes de cada aumento."""
    weeks: list[tuple[int, Week]] = []
    last = len(template.weeks)
    for number, week in enumerate(template.weeks, start=1):
        weeks.append((number, week))
        if joint_care and number % 2 == 0 and number < last:
            weeks.append((number, week))
    return weeks


def schedule(start: date, weekdays: list[int], count: int) -> list[date]:
    """Datas sugeridas: os dias escolhidos, a partir do início, em ordem."""
    dates: list[date] = []
    day = start
    while len(dates) < count:
        if day.weekday() in weekdays:
            dates.append(day)
        day += timedelta(days=1)
    return dates


def is_done(session: PlanSession) -> bool:
    activity = session.completed_activity
    return activity is not None and activity.deleted_at is None


def adaptations(adapted_for: dict) -> list[str]:
    return [text for key, text in ADAPTATION_TEXTS.items() if adapted_for.get(key)]


def _check_weekdays(weekdays: list[int], runs: bool) -> list[int]:
    days = sorted(set(weekdays))
    if len(days) != len(weekdays) or len(days) != SESSIONS_PER_WEEK:
        raise FieldValidationError("weekdays", f"Escolha {SESSIONS_PER_WEEK} dias diferentes.")
    if runs:
        # Inclui domingo → segunda (6 e 0).
        neighbors = {(a, (a + 1) % 7) for a in days}
        if any(b in days for _, b in neighbors):
            raise FieldValidationError(
                "weekdays", "Na corrida, deixe um dia de descanso entre as sessões."
            )
    return days


class PlanService:
    def __init__(self, db: Session) -> None:
        self.db = db

    # --- personalização ---

    def health_flags(self, user: User, template: PlanTemplate) -> dict[str, bool]:
        profile = user.profile
        if profile is None or not active_consent(self.db, user.id, ConsentKind.HEALTH_DATA):
            return {}
        tags = set(profile.limitation_tags or [])
        flags = {}
        if template.runs and tags & JOINT_TAGS:
            flags["joint_care"] = True
        if tags & CARDIO_TAGS:
            flags["medical_clearance_advised"] = True
        return flags

    def readiness_note(self, user: User, template: PlanTemplate) -> str | None:
        if template.kind != "run_10k":
            return None
        since = _now() - _RECENT
        has_base = self.db.scalar(
            select(Activity.id)
            .join(EnduranceDetails)
            .where(
                Activity.user_id == user.id,
                Activity.modality == "run",
                Activity.deleted_at.is_(None),
                Activity.started_at >= since,
                EnduranceDetails.distance_m >= 5000,
            )
            .limit(1)
        )
        return None if has_base else TEN_K_NOTE

    # --- leitura ---

    def _query(self, user: User):
        return (
            select(TrainingPlan)
            .where(TrainingPlan.user_id == user.id)
            .options(
                selectinload(TrainingPlan.sessions).selectinload(PlanSession.completed_activity)
            )
        )

    def list(self, user: User) -> list[TrainingPlan]:
        query = self._query(user).order_by(TrainingPlan.created_at.desc(), TrainingPlan.id.desc())
        return list(self.db.scalars(query.limit(50)))

    def get(self, user: User, plan_id: uuid.UUID) -> TrainingPlan:
        plan = self.db.scalar(self._query(user).where(TrainingPlan.id == plan_id))
        if plan is None:
            raise NotFoundError("Plano não encontrado.")
        return plan

    def _active(self, user: User) -> TrainingPlan | None:
        return self.db.scalar(
            select(TrainingPlan).where(
                TrainingPlan.user_id == user.id, TrainingPlan.status == "active"
            )
        )

    # --- escrita ---

    def create(self, user: User, data: PlanCreate) -> TrainingPlan:
        template = TEMPLATES[data.kind]
        weekdays = _check_weekdays(data.weekdays, template.runs)
        today = _today(user)
        start = data.start_date or today
        if not today <= start <= today + _START_AHEAD:
            raise FieldValidationError(
                "start_date", "Escolha uma data entre hoje e as próximas 4 semanas."
            )
        if (active := self._active(user)) is not None:
            raise PlanInProgressError(active.id)

        flags = self.health_flags(user, template)
        weeks = expanded_weeks(template, flags.get("joint_care", False))
        dates = iter(schedule(start, weekdays, len(weeks) * template.sessions_per_week))
        profile = user.profile
        plan = TrainingPlan(
            user_id=user.id,
            kind=template.kind,
            template_version=template.version,
            start_date=start,
            weekdays=weekdays,
            status="active",
            adapted_for={
                "experience_level": profile.experience_level.value
                if profile and profile.experience_level
                else None,
                **flags,
            },
        )
        position = 0
        for week_number, (template_week, sessions) in enumerate(weeks, start=1):
            for day_index, blocks in enumerate(sessions, start=1):
                position += 1
                plan.sessions.append(
                    PlanSession(
                        position=position,
                        week=week_number,
                        day_index=day_index,
                        template_week=template_week,
                        prescription=blocks,
                        scheduled_date=next(dates),
                    )
                )
        self.db.add(plan)
        self.db.commit()
        logger.info(
            "plan_created",
            extra={"user_id": str(user.id), "plan_id": str(plan.id), "kind": plan.kind},
        )
        return self.get(user, plan.id)

    def end(self, user: User, plan_id: uuid.UUID) -> TrainingPlan:
        plan = self.get(user, plan_id)
        if plan.status != "active":
            raise PlanClosedError
        plan.status = "ended"
        plan.ended_at = _now()
        self.db.commit()
        logger.info("plan_ended", extra={"user_id": str(user.id), "plan_id": str(plan.id)})
        return self.get(user, plan.id)

    def _session(self, plan: TrainingPlan, session_id: uuid.UUID) -> PlanSession:
        for session in plan.sessions:
            if session.id == session_id:
                return session
        raise NotFoundError("Sessão não encontrada.")

    def link(
        self, user: User, plan_id: uuid.UUID, session_id: uuid.UUID, activity_id: uuid.UUID
    ) -> TrainingPlan:
        """Marca a sessão como feita com uma atividade da própria pessoa."""
        plan = self.get(user, plan_id)
        session = self._session(plan, session_id)
        if plan.status != "active":
            raise PlanClosedError
        activity = self.db.scalar(
            select(Activity).where(
                Activity.id == activity_id,
                Activity.user_id == user.id,
                Activity.deleted_at.is_(None),
            )
        )
        if activity is None:
            raise FieldValidationError("activity_id", "Atividade não encontrada.")
        template = TEMPLATES[plan.kind]
        if activity.modality not in _COUNTS_FOR[template.modality]:
            expected = "uma corrida" if template.runs else "uma caminhada"
            raise FieldValidationError("activity_id", f"Esta sessão pede {expected}.")
        if activity.started_at.astimezone(_tz(user)).date() < plan.start_date:
            raise FieldValidationError("activity_id", "A atividade é de antes do início do plano.")
        taken = self.db.scalar(
            select(PlanSession.id).where(
                PlanSession.completed_activity_id == activity.id, PlanSession.id != session.id
            )
        )
        if taken is not None:
            raise FieldValidationError("activity_id", "Esta atividade já conta para outra sessão.")

        if session.completed_activity_id != activity.id:
            session.completed_activity_id = activity.id
            session.completed_activity = activity
            session.completed_at = _now()
        if all(is_done(s) for s in plan.sessions):
            plan.status = "completed"
            plan.ended_at = _now()
        self.db.commit()
        logger.info(
            "plan_session_done",
            extra={"user_id": str(user.id), "plan_id": str(plan.id), "position": session.position},
        )
        return self.get(user, plan.id)

    def unlink(self, user: User, plan_id: uuid.UUID, session_id: uuid.UUID) -> TrainingPlan:
        plan = self.get(user, plan_id)
        session = self._session(plan, session_id)
        if plan.status != "active":
            raise PlanClosedError
        session.completed_activity_id = None
        session.completed_activity = None
        session.completed_at = None
        self.db.commit()
        return self.get(user, plan.id)
