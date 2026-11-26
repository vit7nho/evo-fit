"""Prompts de sistema versionados (AI_DESIGN §5). A versão e o hash do texto vão para
`ai_run_logs`: dá para saber qual prompt produziu cada resposta."""

import hashlib
from dataclasses import dataclass
from functools import cache
from pathlib import Path

CURRENT = "coach.v3"


@dataclass(frozen=True)
class Prompt:
    version: str
    text: str

    @property
    def hash(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8")).hexdigest()[:16]


@cache
def load(version: str = CURRENT) -> Prompt:
    path = Path(__file__).with_name(f"{version}.md")
    return Prompt(version, path.read_text(encoding="utf-8").strip())
