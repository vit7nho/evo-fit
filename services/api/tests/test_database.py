import uuid

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import Engine, inspect
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.models import Base, User, UserProfile
from tests.conftest import alembic_config


def _user(email: str = "ana@example.com") -> User:
    return User(email=email, password_hash="argon2id$placeholder")


def test_migrations_match_orm_models(engine: Engine) -> None:
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], f"Migrações divergem dos models: {diff}"


def test_migrations_downgrade_and_upgrade_cleanly(engine: Engine) -> None:
    command.downgrade(alembic_config(), "base")
    assert set(inspect(engine).get_table_names()) <= {"alembic_version"}
    command.upgrade(alembic_config(), "head")
    assert {"users", "user_profiles", "user_consents", "refresh_tokens"} <= set(
        inspect(engine).get_table_names()
    )


def test_user_ids_are_uuid_v7(db: Session) -> None:
    user = _user()
    db.add(user)
    db.flush()
    assert isinstance(user.id, uuid.UUID)
    assert user.id.version == 7


def test_email_must_be_stored_lowercase(db: Session) -> None:
    db.add(_user("Ana@Example.com"))
    with pytest.raises(IntegrityError, match="email_lowercase"):
        db.flush()


def test_email_is_unique(db: Session) -> None:
    db.add(_user())
    db.flush()
    db.add(_user())
    with pytest.raises(IntegrityError, match="uq_users_email"):
        db.flush()


def test_deleting_user_cascades_to_profile(db: Session) -> None:
    user = _user()
    user.profile = UserProfile(display_name="Ana")
    db.add(user)
    db.flush()
    assert user.profile.preferred_modalities == []

    db.delete(user)
    db.flush()
    assert db.get(UserProfile, user.id) is None
