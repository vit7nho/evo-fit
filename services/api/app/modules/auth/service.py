"""Regras de autenticação: cadastro, login, rotação do refresh e logout (ADR-005)."""

import logging
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import AppError, FieldValidationError, UnauthorizedError
from app.modules.auth import passwords, tokens
from app.modules.auth.models import RefreshToken
from app.modules.auth.schemas import LoginRequest, RegisterRequest, TokenPair
from app.modules.users.models import ConsentKind, User, UserConsent, UserProfile, UserStatus

logger = logging.getLogger(__name__)


class EmailAlreadyRegisteredError(AppError):
    def __init__(self) -> None:
        super().__init__(
            409,
            "email_already_registered",
            "E-mail já cadastrado",
            "Já existe uma conta com este e-mail. Entre ou use outro e-mail.",
        )


class AccountDisabledError(AppError):
    def __init__(self) -> None:
        super().__init__(403, "account_disabled", "Conta desativada", "Esta conta está desativada.")


def _invalid_credentials() -> UnauthorizedError:
    # Mesma resposta para e-mail inexistente e senha errada: não revela contas cadastradas.
    return UnauthorizedError("invalid_credentials", "E-mail ou senha incorretos.")


def _invalid_refresh() -> UnauthorizedError:
    return UnauthorizedError("invalid_refresh_token", "Sessão expirada. Entre novamente.")


class AuthService:
    def __init__(self, db: Session, settings: Settings) -> None:
        self.db = db
        self.settings = settings

    # --- cadastro e login ---

    def register(self, data: RegisterRequest, user_agent: str | None) -> tuple[User, TokenPair]:
        if not data.accept_terms:
            raise FieldValidationError(
                "accept_terms", "É preciso aceitar os Termos de Uso e a Política de Privacidade."
            )
        if problem := passwords.password_policy_error(data.password, data.email):
            raise FieldValidationError("password", problem)
        if self.db.scalar(select(User.id).where(User.email == data.email)) is not None:
            raise EmailAlreadyRegisteredError

        now = datetime.now(UTC)
        user = User(email=data.email, password_hash=passwords.hash_password(data.password))
        user.profile = UserProfile(display_name=data.display_name)
        self.db.add(user)
        try:
            self.db.flush()
        except IntegrityError as exc:
            # Dois cadastros simultâneos com o mesmo e-mail: a constraint única decide.
            self.db.rollback()
            raise EmailAlreadyRegisteredError from exc
        self.db.add(
            UserConsent(
                user_id=user.id,
                kind=ConsentKind.TERMS_PRIVACY,
                version=self.settings.terms_version,
                granted_at=now,
            )
        )
        user.last_login_at = now
        pair = self._issue(user.id, uuid.uuid7(), user_agent, now)
        self.db.commit()
        logger.info("auth_registered", extra={"user_id": str(user.id)})
        return user, pair

    def authenticate(self, data: LoginRequest) -> User:
        user = self.db.scalar(select(User).where(User.email == data.email))
        if user is None:
            passwords.burn_verification_time(data.password)
            raise _invalid_credentials()
        if not passwords.verify_password(user.password_hash, data.password):
            logger.info("auth_login_failed", extra={"user_id": str(user.id)})
            raise _invalid_credentials()
        if user.status is not UserStatus.ACTIVE:
            raise AccountDisabledError
        return user

    def login(self, user: User, password: str, user_agent: str | None) -> TokenPair:
        now = datetime.now(UTC)
        if passwords.needs_rehash(user.password_hash):
            user.password_hash = passwords.hash_password(password)
        user.last_login_at = now
        pair = self._issue(user.id, uuid.uuid7(), user_agent, now)
        self.db.commit()
        logger.info("auth_login", extra={"user_id": str(user.id)})
        return pair

    # --- refresh e logout ---

    def refresh(self, raw_token: str, user_agent: str | None) -> TokenPair:
        now = datetime.now(UTC)
        # FOR UPDATE: duas rotações simultâneas do mesmo token não geram dois sucessores.
        stored = self.db.scalar(
            select(RefreshToken)
            .where(RefreshToken.token_hash == tokens.hash_refresh_token(raw_token))
            .with_for_update()
        )
        if stored is None or stored.revoked_at is not None:
            raise _invalid_refresh()
        if stored.rotated_at is not None:
            # Um token já trocado foi reapresentado: pode ter sido copiado. Encerra a família.
            self._revoke_family(stored.family_id, now)
            self.db.commit()
            logger.warning(
                "auth_refresh_reuse_detected",
                extra={"user_id": str(stored.user_id), "family_id": str(stored.family_id)},
            )
            raise UnauthorizedError(
                "refresh_token_reused", "Sessão encerrada por segurança. Entre novamente."
            )
        if stored.expires_at <= now:
            raise _invalid_refresh()
        user = self.db.get(User, stored.user_id)
        if user is None or user.status is not UserStatus.ACTIVE:
            self._revoke_family(stored.family_id, now)
            self.db.commit()
            raise _invalid_refresh()

        stored.rotated_at = now
        pair = self._issue(stored.user_id, stored.family_id, user_agent, now)
        self.db.commit()
        return pair

    def logout(self, raw_token: str) -> None:
        """Revoga a família do token. Idempotente: token desconhecido não gera erro."""
        stored = self.db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == tokens.hash_refresh_token(raw_token)
            )
        )
        if stored is None:
            return
        self._revoke_family(stored.family_id, datetime.now(UTC))
        self.db.commit()
        logger.info("auth_logout", extra={"user_id": str(stored.user_id)})

    # --- internos ---

    def _issue(
        self, user_id: uuid.UUID, family_id: uuid.UUID, user_agent: str | None, now: datetime
    ) -> TokenPair:
        access_token, expires_in = tokens.create_access_token(user_id, self.settings, now)
        raw, token_hash = tokens.new_refresh_token()
        refresh_ttl = timedelta(days=self.settings.refresh_token_ttl_days)
        self.db.add(
            RefreshToken(
                user_id=user_id,
                family_id=family_id,
                token_hash=token_hash,
                created_at=now,
                expires_at=now + refresh_ttl,
                user_agent=(user_agent or "")[:200] or None,
            )
        )
        return TokenPair(
            access_token=access_token,
            refresh_token=raw,
            expires_in=expires_in,
            refresh_expires_in=int(refresh_ttl.total_seconds()),
        )

    def _revoke_family(self, family_id: uuid.UUID, now: datetime) -> None:
        self.db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
