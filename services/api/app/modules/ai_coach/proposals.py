"""Propostas de alteração da IA (4.6, AI_DESIGN §7, ADR-053).

A IA nunca escreve: `prepare` valida a alteração pelas regras do serviço dono do dado
(fichas ou metas), sem gravar nada nele, e guarda uma proposta `pending`. Só quando a
pessoa confirma, `accept` valida tudo de novo e aplica pelo mesmo serviço, numa
transação. Se a ficha mudou depois da proposta (outra impressão digital), a proposta
falha em vez de sobrescrever uma versão que a IA não viu.
"""

import hashlib
import logging
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Annotated, Any, Literal

from pydantic import Field, StringConstraints
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import AppError, NotFoundError
from app.modules.ai_coach.models import ChangeProposal
from app.modules.ai_coach.tools.base import ToolContext, ToolError, ToolInput
from app.modules.goals import kinds
from app.modules.goals.schemas import GoalCreate
from app.modules.goals.service import GoalService
from app.modules.training.catalog import MAX_SETS
from app.modules.training.models import WorkoutTemplate
from app.modules.training.schemas import ItemIn, PlannedSet, TemplateIn
from app.modules.training.service import TemplateService, template_input
from app.modules.users.models import User

logger = logging.getLogger(__name__)

EXPIRES_AFTER = timedelta(days=7)
# Propostas aguardando resposta numa conversa: acima disso a IA precisa esperar.
MAX_PENDING = 3

Rationale = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=300)]
Sets = Annotated[list[PlannedSet], Field(min_length=1, max_length=MAX_SETS)]


def _now() -> datetime:
    """Relógio das propostas (separado para os testes controlarem a validade)."""
    return datetime.now(UTC)


# --- as alterações que a IA pode propor ---


class AddExercise(ToolInput):
    kind: Literal["template_add_exercise"]
    template_id: uuid.UUID
    exercise_id: uuid.UUID
    planned_sets: Sets
    rest_s: Annotated[int, Field(ge=0, le=900)] | None = None


class ReplaceExercise(ToolInput):
    kind: Literal["template_replace_exercise"]
    template_id: uuid.UUID
    item_id: uuid.UUID = Field(description="Item da ficha (de get_templates).")
    exercise_id: uuid.UUID = Field(description="O novo exercício; as séries continuam.")


class AdjustSets(ToolInput):
    kind: Literal["template_adjust_sets"]
    template_id: uuid.UUID
    item_id: uuid.UUID = Field(description="Item da ficha (de get_templates).")
    planned_sets: Sets


_GOAL_KINDS = "Tipo da meta e os campos do alvo: " + "; ".join(
    f"{k.code} ({', '.join(f.key for f in k.fields)})" for k in kinds.KINDS.values()
)


class CreateGoal(ToolInput):
    kind: Literal["goal_create"]
    goal_kind: str = Field(description=_GOAL_KINDS)
    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    target: dict[str, Any] = Field(description="Alvo nos campos do tipo da meta.")
    target_date: date | None = None


Change = Annotated[
    AddExercise | ReplaceExercise | AdjustSets | CreateGoal, Field(discriminator="kind")
]


# --- textos ---

_SET_KIND = {"warmup": "aquecimento", "drop": "drop", "rest_pause": "rest-pause"}


def _set_text(s: PlannedSet) -> str:
    if s.duration_s is not None:
        text = f"{s.duration_s} s"
    elif s.reps_min is not None and s.reps_max is not None and s.reps_min != s.reps_max:
        text = f"{s.reps_min} a {s.reps_max} reps"
    else:
        reps = s.reps_min or s.reps_max
        text = f"{reps} reps" if reps else "livre"
    if s.load_kg is not None:
        text += f" com {s.load_kg:g} kg"
    if s.kind in _SET_KIND:
        text = f"{_SET_KIND[s.kind]} {text}"
    return text


def describe_sets(sets: list[PlannedSet]) -> str:
    """ "3 séries de 8 a 12 reps" quando as séries são iguais; senão, uma a uma."""
    parts = [_set_text(s) for s in sets]
    if len(set(parts)) == 1:
        n = len(parts)
        return f"{n} série de {parts[0]}" if n == 1 else f"{n} séries de {parts[0]}"
    return ", ".join(parts)


def fingerprint(template: WorkoutTemplate) -> str:
    return hashlib.sha256(template_input(template).model_dump_json().encode()).hexdigest()


# --- validação e montagem ---


class _Plan:
    """A alteração aplicada sobre a ficha atual: a ficha nova e os textos."""

    def __init__(self, data: TemplateIn, summary: str, details: list[str]) -> None:
        self.data = data
        self.summary = summary
        self.details = details


def _item_index(template: WorkoutTemplate, item_id: uuid.UUID) -> int:
    ordered = sorted(template.items, key=lambda i: i.position)
    for index, item in enumerate(ordered):
        if item.id == item_id:
            return index
    raise ToolError("Item não encontrado nesta ficha. Consulte get_templates.")


def _template_plan(db: Session, user: User, template: WorkoutTemplate, change: Any) -> _Plan:
    service = TemplateService(db)
    data = template_input(template)
    items = list(data.items)
    names = {i.exercise_id: i.exercise.name for i in template.items}
    if change.kind == "template_add_exercise":
        items.append(
            ItemIn(
                exercise_id=change.exercise_id,
                planned_sets=change.planned_sets,
                rest_s=change.rest_s,
            )
        )
    else:
        index = _item_index(template, change.item_id)
        old = items[index]
        if change.kind == "template_replace_exercise":
            items[index] = old.model_copy(update={"exercise_id": change.exercise_id})
        else:
            items[index] = old.model_copy(update={"planned_sets": change.planned_sets})
    new = data.model_copy(update={"items": items})
    exercises = service.check(user, new)  # as regras da ficha, sem gravar
    exercise_name = {**names, **{e.id: e.name for e in exercises.values()}}
    ficha = f"“{template.name}”"
    if change.kind == "template_add_exercise":
        name = exercise_name[change.exercise_id]
        return _Plan(
            new,
            f"Acrescentar {name} à ficha {ficha}",
            [f"Séries: {describe_sets(change.planned_sets)}"]
            + ([f"Descanso: {change.rest_s} s"] if change.rest_s is not None else []),
        )
    old = data.items[index]
    before = exercise_name[old.exercise_id]
    if change.kind == "template_replace_exercise":
        after = exercise_name[change.exercise_id]
        if after == before:
            raise ToolError("O exercício novo é o mesmo que já está na ficha.")
        return _Plan(
            new,
            f"Trocar {before} por {after} na ficha {ficha}",
            [f"Séries mantidas: {describe_sets(old.planned_sets)}"],
        )
    old_sets, new_sets = describe_sets(old.planned_sets), describe_sets(change.planned_sets)
    if old_sets == new_sets:
        raise ToolError("As séries propostas são iguais às atuais.")
    return _Plan(
        new,
        f"Ajustar as séries de {before} na ficha {ficha}",
        [f"Antes: {old_sets}", f"Depois: {new_sets}"],
    )


def _goal_data(change: CreateGoal) -> GoalCreate:
    return GoalCreate(
        kind=change.goal_kind,
        title=change.title,
        target=change.target,
        target_date=change.target_date,
    )


def _goal_texts(db: Session, user: User, change: CreateGoal) -> tuple[str, list[str]]:
    kind, target, _ = GoalService(db).check(user, _goal_data(change))
    details = [f"Alvo: {kinds.summarize(kind.code, target)}"]
    if change.target_date:
        details.append(f"Prazo: {change.target_date.strftime('%d/%m/%Y')}")
    return f"Criar a meta “{change.title}” ({kind.label})", details


def _owned_template(db: Session, user: User, template_id: uuid.UUID) -> WorkoutTemplate:
    try:
        return TemplateService(db).get(user, template_id)
    except NotFoundError:
        raise ToolError("Ficha não encontrada. Consulte get_templates.") from None


# --- a ferramenta ---


def prepare(ctx: ToolContext, change: Any, rationale: str) -> ChangeProposal:
    if ctx.conversation_id is None:
        raise ToolError("Propostas só podem ser feitas dentro de uma conversa.")
    pending = ctx.db.scalars(
        select(ChangeProposal).where(
            ChangeProposal.user_id == ctx.user.id,
            ChangeProposal.conversation_id == ctx.conversation_id,
            ChangeProposal.status == "pending",
            ChangeProposal.expires_at > _now(),
        )
    ).all()
    if len(pending) >= MAX_PENDING:
        raise ToolError(
            f"Já há {MAX_PENDING} propostas aguardando a resposta da pessoa nesta conversa. "
            "Peça que ela responda antes de sugerir outra."
        )

    base_hash = None
    if isinstance(change, CreateGoal):
        summary, details = _goal_texts(ctx.db, ctx.user, change)
    else:
        template = _owned_template(ctx.db, ctx.user, change.template_id)
        plan = _template_plan(ctx.db, ctx.user, template, change)
        summary, details, base_hash = plan.summary, plan.details, fingerprint(template)

    now = _now()
    proposal = ChangeProposal(
        user_id=ctx.user.id,
        conversation_id=ctx.conversation_id,
        kind=change.kind,
        payload=change.model_dump(mode="json"),
        base_hash=base_hash,
        summary=summary[:200],
        details=details,
        rationale=rationale,
        status="pending",
        expires_at=now + EXPIRES_AFTER,
        created_at=now,
    )
    ctx.db.add(proposal)
    ctx.db.flush()
    logger.info(
        "ai_proposal_created",
        extra={"user_id": str(ctx.user.id), "proposal_id": str(proposal.id), "kind": change.kind},
    )
    return proposal


# --- decisão da pessoa ---


class ProposalNotPending(AppError):
    def __init__(self, status: str) -> None:
        labels = {
            "accepted": "já foi aplicada",
            "rejected": "já foi recusada",
            "expired": "expirou (vale 7 dias); peça uma nova à IA",
            "failed": "não pôde ser aplicada",
        }
        super().__init__(
            409,
            "proposal_not_pending",
            "Proposta encerrada",
            f"Esta proposta {labels.get(status, 'não está mais aberta')}.",
        )


class ProposalStale(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "proposal_stale",
            "A ficha mudou",
            "A ficha foi alterada depois da sugestão, então nada foi aplicado. "
            "Peça à IA uma sugestão nova.",
        )


_CHANGE_MODELS: dict[str, type[ToolInput]] = {
    "template_add_exercise": AddExercise,
    "template_replace_exercise": ReplaceExercise,
    "template_adjust_sets": AdjustSets,
    "goal_create": CreateGoal,
}


class ProposalService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def _expire(self, proposals: list[ChangeProposal]) -> None:
        now = _now()
        changed = False
        for p in proposals:
            if p.status == "pending" and p.expires_at <= now:
                p.status, p.decided_at, changed = "expired", now, True
        if changed:
            self.db.commit()

    def list(self, user: User, status: str | None = None) -> list[ChangeProposal]:
        proposals = list(
            self.db.scalars(
                select(ChangeProposal)
                .where(ChangeProposal.user_id == user.id)
                .order_by(ChangeProposal.created_at.desc(), ChangeProposal.id.desc())
            )
        )
        self._expire(proposals)
        return [p for p in proposals if status is None or p.status == status]

    def of_messages(self, user: User, message_ids: list[uuid.UUID]) -> list[ChangeProposal]:
        if not message_ids:
            return []
        proposals = list(
            self.db.scalars(
                select(ChangeProposal)
                .where(
                    ChangeProposal.user_id == user.id,
                    ChangeProposal.message_id.in_(message_ids),
                )
                .order_by(ChangeProposal.created_at, ChangeProposal.id)
            )
        )
        self._expire(proposals)
        return proposals

    def get(self, user: User, proposal_id: uuid.UUID) -> ChangeProposal:
        proposal = self.db.scalar(
            select(ChangeProposal).where(
                ChangeProposal.id == proposal_id, ChangeProposal.user_id == user.id
            )
        )
        if proposal is None:
            raise NotFoundError("Proposta não encontrada.")
        self._expire([proposal])
        return proposal

    def _open(self, user: User, proposal_id: uuid.UUID) -> ChangeProposal:
        proposal = self.get(user, proposal_id)
        if proposal.status != "pending":
            raise ProposalNotPending(proposal.status)
        return proposal

    def reject(self, user: User, proposal_id: uuid.UUID) -> ChangeProposal:
        proposal = self._open(user, proposal_id)
        proposal.status, proposal.decided_at = "rejected", _now()
        self.db.commit()
        return proposal

    def _fail(self, proposal: ChangeProposal, message: str) -> None:
        self.db.rollback()
        proposal.status, proposal.decided_at, proposal.result = "failed", _now(), message[:300]
        self.db.commit()

    def accept(self, user: User, proposal_id: uuid.UUID) -> ChangeProposal:
        proposal = self._open(user, proposal_id)
        change: Any = _CHANGE_MODELS[proposal.kind].model_validate(proposal.payload)
        try:
            if isinstance(change, CreateGoal):
                goals = GoalService(self.db)
                goals.check(user, _goal_data(change))
                proposal.status, proposal.decided_at = "accepted", _now()
                goal = goals.create(user, _goal_data(change))  # grava junto com o status
                proposal.result = f"goal:{goal.id}"
            else:
                service = TemplateService(self.db)
                template = service.get(user, change.template_id)
                if fingerprint(template) != proposal.base_hash:
                    self._fail(proposal, ProposalStale().detail or "")
                    raise ProposalStale()
                plan = _template_plan(self.db, user, template, change)
                proposal.status, proposal.decided_at = "accepted", _now()
                proposal.result = f"template:{template.id}"
                service.replace(user, template.id, plan.data)  # grava junto com o status
        except ProposalStale:
            raise
        except ToolError as error:
            self._fail(proposal, str(error))
            raise AppError(422, "proposal_invalid", "Proposta inválida", str(error)) from None
        except AppError as error:
            message = (
                "; ".join(e["message"] for e in error.errors if e.get("message"))
                if error.code == "validation_error"
                else ""
            )
            self._fail(proposal, message or error.detail or error.title)
            raise
        logger.info(
            "ai_proposal_accepted",
            extra={"user_id": str(user.id), "proposal_id": str(proposal.id)},
        )
        return proposal
