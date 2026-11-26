"""Verificações de saída (AI_DESIGN §6).

- A resposta tem tamanho máximo (corte com reticências).
- Números citados são conferidos, de forma heurística, contra os dados que a rodada
  consultou: um número que não aparece em nenhum resultado (nem em escala comum —
  km/m, min/s — nem arredondado) conta como “não verificado”. Na v1 isso só vai
  para o registro da execução; não bloqueia a resposta.
"""

import re

MAX_ANSWER_CHARS = 4000

# 1.234,5 · 6,5 · 1200 · 5.4 (decimais com vírgula ou ponto; milhar com ponto)
_NUMBER = re.compile(r"(?<![\w.,])\d+(?:[.,]\d+)*")
_CLOCK = re.compile(r"\b(\d{1,2}):([0-5]\d)(?::([0-5]\d))?\b")
_DATE = re.compile(r"\b\d{1,4}[/-]\d{1,2}(?:[/-]\d{1,4})?\b")
_JSON_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")
# Escalas comuns entre o que as ferramentas devolvem e o que se fala (m↔km, s↔min, s↔h).
_SCALES = (1, 1000, 1 / 1000, 60, 1 / 60, 3600, 1 / 3600)
# Inteiros pequenos (contagens, “3 dicas”) não são checados.
_SMALL = 10


def cap(text: str, limit: int = MAX_ANSWER_CHARS) -> str:
    text = text.strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _readings(token: str) -> set[float]:
    """Leituras possíveis de um número escrito em PT-BR (ou com ponto decimal)."""
    out: set[float] = set()
    if "," in token:
        out.add(float(token.replace(".", "").replace(",", ".")))
    else:
        out.add(float(token.replace(".", "")))  # 1.200 = mil e duzentos
        if token.count(".") == 1:
            out.add(float(token))  # 5.4 = cinco vírgula quatro
    return out


def _decimals(token: str) -> int:
    for sep in (",", "."):
        if sep in token:
            return len(token.rsplit(sep, 1)[1])
    return 0


def _matches(value: float, decimals: int, known: list[float]) -> bool:
    for source in known:
        for scale in _SCALES:
            scaled = source * scale
            if abs(round(scaled, decimals) - value) < 1e-9 or abs(scaled - value) < 1e-6:
                return True
    return False


def unverified_numbers(answer: str, sources: list[str]) -> list[str]:
    # Sem sinal: o texto escreve "1,5 kg a menos" para uma variação de -1.5 (5.4).
    known = [abs(float(n)) for s in sources for n in _JSON_NUMBER.findall(s)]
    missing: list[str] = []

    def check_clock(match: re.Match[str]) -> str:
        h_or_m, m_or_s, s = match.groups()
        seconds = (
            int(h_or_m) * 3600 + int(m_or_s) * 60 + int(s)
            if s is not None
            else int(h_or_m) * 60 + int(m_or_s)
        )
        if not _matches(float(seconds), 0, known) and not (
            s is None and _matches(float(int(h_or_m) * 3600 + int(m_or_s) * 60), 0, known)
        ):
            missing.append(match.group(0))
        return " "

    text = _CLOCK.sub(check_clock, _DATE.sub(" ", answer))
    for token in _NUMBER.findall(text):
        readings = _readings(token)
        if all(r.is_integer() and r <= _SMALL for r in readings):
            continue
        decimals = _decimals(token) if "," in token or token.count(".") == 1 else 0
        if not any(_matches(r, decimals if not r.is_integer() else 0, known) for r in readings):
            missing.append(token)
    return missing
