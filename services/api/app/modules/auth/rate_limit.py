"""Limite de tentativas em memória (janela deslizante).

Suficiente para um único processo da API. Com várias instâncias, o estado precisaria ir
para um armazenamento compartilhado (ex.: Redis) — registrado em docs/DECISIONS.md.
"""

import math
import threading
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass

from app.core.errors import AppError


@dataclass(frozen=True)
class Limit:
    max_hits: int
    window_s: float


# Regras de autenticação (docs/SECURITY_PRIVACY.md §2).
LOGIN_PER_IP = Limit(max_hits=20, window_s=5 * 60)
LOGIN_FAILURES_PER_EMAIL = Limit(max_hits=5, window_s=15 * 60)
REGISTER_PER_IP = Limit(max_hits=5, window_s=60 * 60)
REFRESH_PER_IP = Limit(max_hits=60, window_s=5 * 60)


class TooManyRequestsError(AppError):
    def __init__(self, retry_after_s: int) -> None:
        super().__init__(
            429,
            "too_many_requests",
            "Muitas tentativas",
            "Muitas tentativas em pouco tempo. Aguarde um pouco e tente novamente.",
            headers={"Retry-After": str(retry_after_s)},
        )


class RateLimiter:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def _window(self, key: str, limit: Limit, now: float) -> deque[float]:
        hits = self._hits.setdefault(key, deque())
        while hits and hits[0] <= now - limit.window_s:
            hits.popleft()
        return hits

    @staticmethod
    def _ensure_allowed(hits: deque[float], limit: Limit, now: float) -> None:
        if len(hits) >= limit.max_hits:
            retry_after = math.ceil(hits[0] + limit.window_s - now)
            raise TooManyRequestsError(max(retry_after, 1))

    def check(self, key: str, limit: Limit) -> None:
        """Levanta 429 se o limite já foi atingido, sem registrar uma nova ocorrência."""
        with self._lock:
            now = self._clock()
            self._ensure_allowed(self._window(key, limit, now), limit, now)

    def hit(self, key: str, limit: Limit) -> None:
        """Verifica o limite e registra uma ocorrência."""
        with self._lock:
            now = self._clock()
            hits = self._window(key, limit, now)
            self._ensure_allowed(hits, limit, now)
            hits.append(now)

    def record(self, key: str, limit: Limit) -> None:
        """Registra uma ocorrência sem verificar (ex.: uma falha de login)."""
        with self._lock:
            now = self._clock()
            self._window(key, limit, now).append(now)

    def reset(self, key: str) -> None:
        with self._lock:
            self._hits.pop(key, None)
