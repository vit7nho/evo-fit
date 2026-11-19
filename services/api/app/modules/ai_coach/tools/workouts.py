"""Ferramentas de musculação: treinos, treino em andamento, detalhe de um treino,
histórico de um exercício e busca no catálogo.

Tudo passa pelos serviços da API, que filtram pelo dono: um id de treino de outra
pessoa dá "não encontrado", como no app. Mesmas regras de contagem do histórico
(2.8): aquecimento não é série; drop e rest-pause não são séries novas, mas entram
no volume (carga externa vezes repetições).
"""

import uuid
from datetime import UTC, datetime, time, timedelta
from typing import Any

from pydantic import Field, model_validator
from sqlalchemy import func, select

from app.modules.activities.models import Activity
from app.modules.ai_coach.tools.base import (
    PeriodInput,
    Tool,
    ToolContext,
    ToolError,
    ToolInput,
    capped,
)
from app.modules.analytics.service import tz
from app.modules.exercises import catalog
from app.modules.exercises.models import Exercise
from app.modules.exercises.service import ExerciseService
from app.modules.history import router as history_api
from app.modules.sessions.models import SetEntry, WorkoutSession
from app.modules.sessions.service import SessionService, elapsed_s

E1RM_NOTE = "1RM estimado pela fórmula de Epley: estimativa, não teste de carga máxima."


def _bounds(ctx: ToolContext, start, end) -> tuple[datetime, datetime]:
    zone = tz(ctx.user)
    lower = datetime.combine(start, time.min, zone).astimezone(UTC)
    upper = datetime.combine(end + timedelta(days=1), time.min, zone).astimezone(UTC)
    return lower, upper


def _local(ctx: ToolContext, moment: datetime) -> str:
    return moment.astimezone(tz(ctx.user)).isoformat(timespec="minutes")


def _set(s: SetEntry) -> dict[str, Any]:
    return {
        "kind": s.kind,
        "segment": s.parent_set_id is not None,
        "reps": s.reps,
        "load_kg": s.load_kg,
        "duration_s": s.duration_s,
        "rir": s.rir,
        "rpe": s.rpe,
        "to_failure": s.to_failure,
    }


def _totals(session: WorkoutSession) -> tuple[int, float]:
    sets, volume = 0, 0.0
    for entry in session.exercises:
        for s in entry.sets:
            if s.kind == "warmup":
                continue
            if s.parent_set_id is None:
                sets += 1
            if entry.exercise.load_type == "external" and s.load_kg and s.reps:
                volume += s.load_kg * s.reps
    return sets, round(volume, 2)


# --- get_workout_history ---


class HistoryInput(PeriodInput):
    limit: int = Field(default=10, ge=1, le=20, description="Quantos treinos (1 a 20).")


def workout_history(ctx: ToolContext, args: HistoryInput) -> dict[str, Any]:
    start, end = args.period(ctx)
    lower, upper = _bounds(ctx, start, end)
    where = (
        WorkoutSession.user_id == ctx.user.id,
        WorkoutSession.status == "completed",
        Activity.deleted_at.is_(None),
        Activity.started_at >= lower,
        Activity.started_at < upper,
    )
    joined = select(WorkoutSession).join(Activity, Activity.id == WorkoutSession.activity_id)
    total = ctx.db.scalar(joined.with_only_columns(func.count()).where(*where)) or 0
    sessions = ctx.db.scalars(
        joined.where(*where)
        .order_by(Activity.started_at.desc(), WorkoutSession.id.desc())
        .limit(args.limit)
    )
    items = []
    for session in sessions:
        sets, volume = _totals(session)
        items.append(
            {
                "session_id": session.id,
                "name": session.name,
                "started_at": _local(ctx, session.activity.started_at),
                "duration_s": session.activity.duration_s,
                "sets": sets,
                "volume_kg": volume,
                "exercises": [e.exercise.name for e in session.exercises],
            }
        )
    return {
        "from_date": start,
        "to_date": end,
        "total_sessions": total,
        "items": items,
        "truncated": total > len(items),
    }


# --- get_current_session ---


class NoInput(ToolInput):
    pass


def current_session(ctx: ToolContext, args: NoInput) -> dict[str, Any]:
    session = SessionService(ctx.db).current(ctx.user)
    if session is None:
        return {"session": None, "note": "Nenhum treino em andamento."}
    sets, volume = _totals(session)
    return {
        "session": {
            "session_id": session.id,
            "name": session.name,
            "status": session.status,
            "started_at": _local(ctx, session.activity.started_at),
            "elapsed_s": elapsed_s(session),
            "sets": sets,
            "volume_kg": volume,
            "exercises": [
                {
                    "name": e.exercise.name,
                    "sets_done": sum(1 for s in e.sets if s.parent_set_id is None),
                }
                for e in session.exercises
            ],
        }
    }


# --- get_session_detail ---


class SessionInput(ToolInput):
    session_id: uuid.UUID = Field(description="Id do treino (de get_workout_history).")


def session_detail(ctx: ToolContext, args: SessionInput) -> dict[str, Any]:
    session = SessionService(ctx.db).get(ctx.user, args.session_id)
    sets, volume = _totals(session)
    records = (
        history_api.session_events(ctx.db, ctx.user, session)
        if session.status == "completed"
        else []
    )
    names = {e.exercise.id: e.exercise.name for e in session.exercises}
    return {
        "session_id": session.id,
        "name": session.name,
        "status": session.status,
        "started_at": _local(ctx, session.activity.started_at),
        "duration_s": session.activity.duration_s,
        "perceived_effort": session.activity.perceived_effort,
        "sets": sets,
        "volume_kg": volume,
        "exercises": [
            {
                "exercise_id": e.exercise.id,
                "name": e.exercise.name,
                "load_type": e.exercise.load_type,
                "sets": [_set(s) for s in sorted(e.sets, key=lambda s: s.position)],
            }
            for e in session.exercises
        ],
        "records": [
            {
                "exercise": names.get(r.exercise_id),
                "kind": r.kind,
                "value": r.value,
                "reps": r.reps,
                "previous": r.previous,
            }
            for r in records
        ],
    }


# --- get_exercise_history ---


class ExerciseHistoryInput(PeriodInput):
    exercise_id: uuid.UUID | None = Field(default=None, description="Id do exercício.")
    name: str | None = Field(
        default=None, min_length=2, max_length=80, description="Nome, se não souber o id."
    )

    @model_validator(mode="after")
    def _one_of(self) -> ExerciseHistoryInput:
        if self.exercise_id is None and self.name is None:
            raise ValueError("Informe exercise_id ou name.")
        return self


def _resolve(ctx: ToolContext, args: ExerciseHistoryInput) -> Exercise | list[Exercise]:
    service = ExerciseService(ctx.db)
    if args.exercise_id is not None:
        return service.get(ctx.user, args.exercise_id)
    found = service.list(ctx.user, q=args.name)
    exact = [e for e in found if e.search_name == catalog.search_key(args.name or "")]
    if len(exact) == 1 or len(found) == 1:
        return (exact or found)[0]
    if not found:
        raise ToolError(f"Nenhum exercício encontrado com o nome “{args.name}”.")
    return found


def exercise_history(ctx: ToolContext, args: ExerciseHistoryInput) -> dict[str, Any]:
    resolved = _resolve(ctx, args)
    if isinstance(resolved, list):
        return {
            "ambiguous": True,
            "candidates": capped([{"exercise_id": e.id, "name": e.name} for e in resolved], 10),
            "note": "Mais de um exercício com esse nome: escolha um id.",
        }
    history = history_api.exercise_history(resolved.id, ctx.user, ctx.db, limit=20, before=None)
    start, end = (args.from_date, args.to_date) if args.from_date or args.to_date else (None, None)
    if start or end:
        start, end = args.period(ctx)
    sessions = []
    for item in history.sessions:
        day = item.started_at.astimezone(tz(ctx.user)).date()
        if start and not start <= day <= end:
            continue
        sessions.append(
            {
                "session_id": item.session_id,
                "date": day,
                "sets": [
                    {
                        k: getattr(s, k)
                        for k in ("kind", "reps", "load_kg", "duration_s", "to_failure")
                    }
                    | {"segment": s.is_segment}
                    for s in item.sets
                ],
                "volume_kg": item.volume_kg,
                "best_e1rm_kg": item.best_e1rm,
            }
        )
    e1rms = [(s["date"], s["best_e1rm_kg"]) for s in reversed(sessions) if s["best_e1rm_kg"]]
    return {
        "exercise": {
            "exercise_id": resolved.id,
            "name": resolved.name,
            "load_type": resolved.load_type,
        },
        "records": [r.model_dump(exclude={"session_id"}) for r in history.records],
        "sessions": sessions,
        "e1rm_trend": {
            "first": {"date": e1rms[0][0], "kg": e1rms[0][1]} if e1rms else None,
            "last": {"date": e1rms[-1][0], "kg": e1rms[-1][1]} if e1rms else None,
            "note": E1RM_NOTE,
        },
        "truncated": history.next_before is not None,
    }


# --- search_exercises ---

# Equipamentos do perfil com o mesmo código no catálogo (regra do app, 2.4).
_SAME_CODE = {"barbell", "dumbbells", "kettlebell", "bands", "pull_up_bar", "bodyweight"}


def available_equipment(profile_equipment: list[str]) -> set[str] | None:
    """O que a pessoa consegue usar; nulo = sem restrição (academia ou nada marcado)."""
    if not profile_equipment or "gym" in profile_equipment:
        return None
    return {e for e in profile_equipment if e in _SAME_CODE} | {"bodyweight"}


class SearchInput(ToolInput):
    query: str | None = Field(default=None, max_length=80, description="Palavras do nome.")
    muscle_id: str | None = Field(
        default=None, description="Músculo (chest, lats, quads, glutes, hamstrings...)."
    )
    only_my_equipment: bool = Field(
        default=True, description="Só exercícios possíveis com o equipamento do perfil."
    )


def search_exercises(ctx: ToolContext, args: SearchInput) -> dict[str, Any]:
    if args.muscle_id and args.muscle_id not in catalog.MUSCLE_NAMES:
        raise ToolError(
            f"Músculo desconhecido: {args.muscle_id}. Use um de: "
            + ", ".join(catalog.MUSCLE_NAMES)
            + "."
        )
    profile = ctx.user.profile
    allowed = available_equipment(list(profile.equipment or [])) if profile else None
    found = ExerciseService(ctx.db).list(
        ctx.user,
        q=args.query,
        muscle=args.muscle_id,
        equipment=sorted(allowed) if args.only_my_equipment and allowed else (),
    )
    result = capped(
        [
            {
                "exercise_id": e.id,
                "name": e.name,
                "equipment": catalog.EQUIPMENT.get(e.equipment, e.equipment),
                "muscles": [
                    {"muscle_id": m.muscle_group_id, "role": m.role.value}
                    for m in sorted(e.muscles, key=lambda m: m.role.value != "primary")
                ],
                "custom": e.owner_user_id is not None,
            }
            for e in found
        ],
        20,
    )
    result["equipment_filter"] = sorted(allowed) if args.only_my_equipment and allowed else None
    return result


TOOLS = (
    Tool(
        name="get_workout_history",
        description=(
            "Treinos de musculação concluídos no período, do mais recente: nome, início, "
            "duração, séries válidas, volume (kg) e exercícios. Traz o total do período."
        ),
        input_model=HistoryInput,
        handler=workout_history,
    ),
    Tool(
        name="get_current_session",
        description="O treino de musculação em andamento ou pausado, se houver.",
        input_model=NoInput,
        handler=current_session,
    ),
    Tool(
        name="get_session_detail",
        description=(
            "Detalhe de um treino: cada exercício com as séries (tipo, repetições, carga, "
            "falha, segmentos de drop/rest-pause) e os recordes batidos nele."
        ),
        input_model=SessionInput,
        handler=session_detail,
    ),
    Tool(
        name="get_exercise_history",
        description=(
            "Histórico de um exercício (por id ou nome): recordes, as séries de cada treino "
            "(até 20, do mais recente) e a evolução do 1RM estimado."
        ),
        input_model=ExerciseHistoryInput,
        handler=exercise_history,
    ),
    Tool(
        name="search_exercises",
        description=(
            "Busca no catálogo de exercícios (e nos próprios da pessoa) por nome e/ou "
            "músculo, por padrão só os possíveis com o equipamento do perfil."
        ),
        input_model=SearchInput,
        handler=search_exercises,
    ),
)
