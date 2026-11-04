import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.dependencies import CurrentUser
from app.modules.plans.models import TrainingPlan
from app.modules.plans.schemas import (
    PlanBlock,
    PlanCreate,
    PlanOut,
    PlanSessionOut,
    PlanSummaryOut,
    PlanTemplateOut,
    SessionActivity,
)
from app.modules.plans.service import (
    PlanService,
    adaptations,
    expanded_weeks,
    is_done,
)
from app.modules.plans.templates import TEMPLATES, describe, session_seconds

router = APIRouter(tags=["planos"])

DbSession = Annotated[Session, Depends(get_db)]


def _summary_fields(plan: TrainingPlan) -> dict:
    template = TEMPLATES[plan.kind]
    done = [is_done(s) for s in plan.sessions]
    next_session = next((s for s, d in zip(plan.sessions, done, strict=True) if not d), None)
    return {
        "id": plan.id,
        "kind": plan.kind,
        "title": template.title,
        "modality": template.modality,
        "template_version": plan.template_version,
        "status": plan.status,
        "start_date": plan.start_date,
        "weekdays": plan.weekdays,
        "weeks": max((s.week for s in plan.sessions), default=0),
        "current_week": next_session.week
        if next_session
        else max((s.week for s in plan.sessions), default=0),
        "total_sessions": len(plan.sessions),
        "completed_sessions": sum(done),
        "next_session_id": next_session.id if next_session and plan.status == "active" else None,
        "adaptations": adaptations(plan.adapted_for),
        "created_at": plan.created_at,
        "ended_at": plan.ended_at,
    }


def _summary(plan: TrainingPlan) -> PlanSummaryOut:
    return PlanSummaryOut(**_summary_fields(plan))


def _out(plan: TrainingPlan) -> PlanOut:
    return PlanOut(
        **_summary_fields(plan),
        sessions=[
            PlanSessionOut(
                id=s.id,
                position=s.position,
                week=s.week,
                day_index=s.day_index,
                scheduled_date=s.scheduled_date,
                blocks=[PlanBlock(**b) for b in s.prescription],
                total_s=session_seconds(s.prescription),
                summary=describe(s.prescription),
                completed_activity_id=s.completed_activity_id if is_done(s) else None,
                completed_at=s.completed_at if is_done(s) else None,
            )
            for s in plan.sessions
        ],
    )


@router.get(
    "/training-plan-templates",
    response_model=list[PlanTemplateOut],
    summary="Planos disponíveis, já com os ajustes para a pessoa",
)
def plan_templates(user: CurrentUser, db: DbSession) -> list[PlanTemplateOut]:
    service = PlanService(db)
    result = []
    for template in TEMPLATES.values():
        flags = service.health_flags(user, template)
        result.append(
            PlanTemplateOut(
                kind=template.kind,  # type: ignore[arg-type]
                version=template.version,
                title=template.title,
                summary=template.summary,
                modality=template.modality,  # type: ignore[arg-type]
                prerequisite=template.prerequisite,
                sessions_per_week=template.sessions_per_week,
                weeks=len(expanded_weeks(template, flags.get("joint_care", False))),
                adaptations=adaptations(flags),
                note=service.readiness_note(user, template),
            )
        )
    return result


@router.get(
    "/training-plans",
    response_model=list[PlanSummaryOut],
    summary="Planos da pessoa, do mais recente",
)
def list_plans(user: CurrentUser, db: DbSession) -> list[PlanSummaryOut]:
    return [_summary(p) for p in PlanService(db).list(user)]


@router.post(
    "/training-plans",
    response_model=PlanOut,
    status_code=status.HTTP_201_CREATED,
    summary="Começa um plano (409 se já houver um em andamento)",
)
def create_plan(data: PlanCreate, user: CurrentUser, db: DbSession, response: Response) -> PlanOut:
    plan = PlanService(db).create(user, data)
    response.headers["Location"] = f"/api/v1/training-plans/{plan.id}"
    return _out(plan)


@router.get("/training-plans/{plan_id}", response_model=PlanOut, summary="Um plano e suas sessões")
def get_plan(plan_id: uuid.UUID, user: CurrentUser, db: DbSession) -> PlanOut:
    return _out(PlanService(db).get(user, plan_id))


@router.post(
    "/training-plans/{plan_id}/end",
    response_model=PlanOut,
    summary="Encerra o plano antes do fim (o histórico fica)",
)
def end_plan(plan_id: uuid.UUID, user: CurrentUser, db: DbSession) -> PlanOut:
    return _out(PlanService(db).end(user, plan_id))


@router.put(
    "/training-plans/{plan_id}/sessions/{plan_session_id}/activity",
    response_model=PlanOut,
    summary="Marca a sessão como feita com uma atividade registrada",
)
def link_activity(
    plan_id: uuid.UUID,
    plan_session_id: uuid.UUID,
    data: SessionActivity,
    user: CurrentUser,
    db: DbSession,
) -> PlanOut:
    return _out(PlanService(db).link(user, plan_id, plan_session_id, data.activity_id))


@router.delete(
    "/training-plans/{plan_id}/sessions/{plan_session_id}/activity",
    response_model=PlanOut,
    summary="Desfaz a marcação da sessão (a atividade fica)",
)
def unlink_activity(
    plan_id: uuid.UUID, plan_session_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> PlanOut:
    return _out(PlanService(db).unlink(user, plan_id, plan_session_id))
