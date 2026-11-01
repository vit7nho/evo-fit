"""Sessões de treino: atividades, sessões, exercícios da sessão e séries.

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "activities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("modality", sa.String(16), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_s", sa.Integer(), nullable=True),
        sa.Column("perceived_effort", sa.SmallInteger(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("external_id", sa.String(128), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "perceived_effort BETWEEN 1 AND 10", name=op.f("ck_activities_effort_range")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_activities_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_activities")),
    )
    op.create_index(op.f("ix_activities_user_id"), "activities", ["user_id"])
    op.create_index(
        "uq_activities_user_source_external",
        "activities",
        ["user_id", "source", "external_id"],
        unique=True,
        postgresql_where=sa.text("external_id IS NOT NULL"),
    )

    op.create_table(
        "workout_sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("activity_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(60), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("paused_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("paused_total_s", sa.Integer(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["activity_id"],
            ["activities.id"],
            name=op.f("fk_workout_sessions_activity_id_activities"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_workout_sessions_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["template_id"],
            ["workout_templates.id"],
            name=op.f("fk_workout_sessions_template_id_workout_templates"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_workout_sessions")),
        sa.UniqueConstraint("activity_id", name=op.f("uq_workout_sessions_activity_id")),
    )
    op.create_index(
        "uq_workout_sessions_open_per_user",
        "workout_sessions",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('in_progress', 'paused')"),
    )
    op.create_index("ix_workout_sessions_user_id_status", "workout_sessions", ["user_id", "status"])

    # Grupos agora pertencem a uma ficha ou a uma sessão.
    op.add_column("exercise_groups", sa.Column("session_id", sa.Uuid(), nullable=True))
    op.alter_column("exercise_groups", "template_id", nullable=True)
    op.create_foreign_key(
        op.f("fk_exercise_groups_session_id_workout_sessions"),
        "exercise_groups",
        "workout_sessions",
        ["session_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(op.f("ix_exercise_groups_session_id"), "exercise_groups", ["session_id"])
    op.create_check_constraint(
        op.f("ck_exercise_groups_template_or_session"),
        "exercise_groups",
        "(template_id IS NULL) <> (session_id IS NULL)",
    )

    op.create_table(
        "session_exercises",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("group_id", sa.Uuid(), nullable=True),
        sa.Column("planned_sets", postgresql.JSONB(), nullable=True),
        sa.Column("rest_s", sa.SmallInteger(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["workout_sessions.id"],
            name=op.f("fk_session_exercises_session_id_workout_sessions"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["exercise_id"],
            ["exercises.id"],
            name=op.f("fk_session_exercises_exercise_id_exercises"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["group_id"],
            ["exercise_groups.id"],
            name=op.f("fk_session_exercises_group_id_exercise_groups"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_session_exercises")),
    )
    op.create_index(op.f("ix_session_exercises_exercise_id"), "session_exercises", ["exercise_id"])
    op.create_index(
        "ix_session_exercises_session_id_position", "session_exercises", ["session_id", "position"]
    )

    op.create_table(
        "set_entries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("session_exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("parent_set_id", sa.Uuid(), nullable=True),
        sa.Column("reps", sa.SmallInteger(), nullable=True),
        sa.Column("load_kg", sa.Numeric(6, 2), nullable=True),
        sa.Column("duration_s", sa.Integer(), nullable=True),
        sa.Column("rir", sa.SmallInteger(), nullable=True),
        sa.Column("rpe", sa.Numeric(3, 1), nullable=True),
        sa.Column("to_failure", sa.Boolean(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "(kind IN ('drop', 'rest_pause', 'cluster')) = (parent_set_id IS NOT NULL)",
            name=op.f("ck_set_entries_segment_has_parent"),
        ),
        sa.ForeignKeyConstraint(
            ["session_exercise_id"],
            ["session_exercises.id"],
            name=op.f("fk_set_entries_session_exercise_id_session_exercises"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["parent_set_id"],
            ["set_entries.id"],
            name=op.f("fk_set_entries_parent_set_id_set_entries"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_set_entries")),
    )
    op.create_index(
        op.f("ix_set_entries_session_exercise_id"), "set_entries", ["session_exercise_id"]
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_set_entries_session_exercise_id"), table_name="set_entries")
    op.drop_table("set_entries")
    op.drop_index("ix_session_exercises_session_id_position", table_name="session_exercises")
    op.drop_index(op.f("ix_session_exercises_exercise_id"), table_name="session_exercises")
    op.drop_table("session_exercises")
    op.drop_constraint(
        op.f("ck_exercise_groups_template_or_session"), "exercise_groups", type_="check"
    )
    op.drop_index(op.f("ix_exercise_groups_session_id"), table_name="exercise_groups")
    op.drop_constraint(
        op.f("fk_exercise_groups_session_id_workout_sessions"),
        "exercise_groups",
        type_="foreignkey",
    )
    op.execute("DELETE FROM exercise_groups WHERE template_id IS NULL")
    op.alter_column("exercise_groups", "template_id", nullable=False)
    op.drop_column("exercise_groups", "session_id")
    op.drop_index("ix_workout_sessions_user_id_status", table_name="workout_sessions")
    op.drop_index("uq_workout_sessions_open_per_user", table_name="workout_sessions")
    op.drop_table("workout_sessions")
    op.drop_index("uq_activities_user_source_external", table_name="activities")
    op.drop_index(op.f("ix_activities_user_id"), table_name="activities")
    op.drop_table("activities")
