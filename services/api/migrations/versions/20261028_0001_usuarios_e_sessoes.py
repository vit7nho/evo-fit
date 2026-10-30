"""usuários, perfil, consentimentos e refresh tokens

Revision ID: 0001
Revises:
Create Date: 2026-10-28
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

user_status = postgresql.ENUM("active", "disabled", name="user_status", create_type=False)
sex_for_calculations = postgresql.ENUM(
    "female", "male", "unspecified", name="sex_for_calculations", create_type=False
)
unit_system = postgresql.ENUM("metric", "imperial", name="unit_system", create_type=False)
experience_level = postgresql.ENUM(
    "beginner", "intermediate", "advanced", name="experience_level", create_type=False
)
consent_kind = postgresql.ENUM(
    "terms_privacy", "health_data", "ai_processing", name="consent_kind", create_type=False
)
ENUMS = (user_status, sex_for_calculations, unit_system, experience_level, consent_kind)


def upgrade() -> None:
    bind = op.get_bind()
    for enum in ENUMS:
        enum.create(bind, checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("status", user_status, nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint("email = lower(email)", name=op.f("ck_users_email_lowercase")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("email", name=op.f("uq_users_email")),
    )

    op.create_table(
        "user_profiles",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("display_name", sa.String(60), nullable=False),
        sa.Column("birth_year", sa.SmallInteger(), nullable=True),
        sa.Column("sex_for_calculations", sex_for_calculations, nullable=True),
        sa.Column("timezone", sa.String(64), nullable=False),
        sa.Column("unit_system", unit_system, nullable=False),
        sa.Column("experience_level", experience_level, nullable=True),
        sa.Column("weekly_availability", postgresql.JSONB(), nullable=True),
        sa.Column("preferred_modalities", postgresql.ARRAY(sa.String(32)), nullable=False),
        sa.Column("equipment", postgresql.ARRAY(sa.String(32)), nullable=False),
        sa.Column("dietary_preferences", postgresql.ARRAY(sa.String(32)), nullable=False),
        sa.Column("limitation_tags", postgresql.ARRAY(sa.String(48)), nullable=False),
        sa.Column("limitations_note", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "birth_year BETWEEN 1900 AND 2100", name=op.f("ck_user_profiles_birth_year_range")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_user_profiles_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", name=op.f("pk_user_profiles")),
    )

    op.create_table(
        "user_consents",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", consent_kind, nullable=False),
        sa.Column("version", sa.String(20), nullable=False),
        sa.Column("granted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_user_consents_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_consents")),
    )
    op.create_index(op.f("ix_user_consents_user_id"), "user_consents", ["user_id"])

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rotated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("user_agent", sa.String(200), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_refresh_tokens_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_refresh_tokens")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_refresh_tokens_token_hash")),
    )
    op.create_index(op.f("ix_refresh_tokens_user_id"), "refresh_tokens", ["user_id"])
    op.create_index(op.f("ix_refresh_tokens_family_id"), "refresh_tokens", ["family_id"])


def downgrade() -> None:
    op.drop_table("refresh_tokens")
    op.drop_table("user_consents")
    op.drop_table("user_profiles")
    op.drop_table("users")
    bind = op.get_bind()
    for enum in reversed(ENUMS):
        enum.drop(bind, checkfirst=True)
