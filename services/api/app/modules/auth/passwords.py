"""Hash (Argon2id) e política de senhas (docs/SECURITY_PRIVACY.md §2)."""

from functools import lru_cache
from pathlib import Path

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

MIN_LENGTH = 10
MAX_LENGTH = 128

_COMMON_FILE = Path(__file__).with_name("data") / "common_passwords.txt"

# Parâmetros padrão do argon2-cffi: Argon2id, perfil de baixa memória da RFC 9106.
_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except VerificationError, InvalidHashError:
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


@lru_cache
def _dummy_hash() -> str:
    return _hasher.hash("evofit-dummy-password-for-timing")


def burn_verification_time(password: str) -> None:
    """Executa uma verificação descartável quando o e-mail não existe.

    Assim a resposta de login leva o mesmo tempo com e sem conta, e o tempo não revela
    quais e-mails estão cadastrados.
    """
    verify_password(_dummy_hash(), password)


@lru_cache
def _common_passwords() -> frozenset[str]:
    lines = _COMMON_FILE.read_text(encoding="utf-8").splitlines()
    return frozenset(line.strip().lower() for line in lines if line and not line.startswith("#"))


def password_policy_error(password: str, email: str) -> str | None:
    """Mensagem em PT-BR do primeiro problema encontrado, ou None se a senha é aceitável."""
    if len(password) < MIN_LENGTH:
        return f"A senha deve ter pelo menos {MIN_LENGTH} caracteres."
    if len(password) > MAX_LENGTH:
        return f"A senha deve ter no máximo {MAX_LENGTH} caracteres."
    lowered = password.lower()
    if lowered in _common_passwords() or len(set(lowered)) <= 2:
        return "Essa senha é muito comum. Escolha outra."
    local_part = email.split("@", 1)[0].lower()
    if len(local_part) >= 4 and local_part in lowered:
        return "A senha não pode conter o seu e-mail."
    return None
