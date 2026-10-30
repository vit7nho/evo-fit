"""Importa todos os models para registrá-los no metadata (usado pelo Alembic e pelos testes)."""

from app.db.base import Base
from app.modules.auth.models import RefreshToken
from app.modules.users.models import User, UserConsent, UserProfile

__all__ = ["Base", "RefreshToken", "User", "UserConsent", "UserProfile"]
