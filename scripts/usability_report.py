"""Resume os testes de usabilidade da etapa 5.7 (docs/USABILIDADE.md).

Lê as planilhas anônimas de docs/usabilidade/ e escreve o relatório em Markdown:
conclusão, tempo, erros e facilidade (SEQ) por tarefa, e a nota SUS por participante.

Uso (na raiz do repositório):
    python scripts/usability_report.py [--out docs/usabilidade/relatorio.md]

Sem --out, imprime o relatório. As planilhas usam só códigos (P1, P2…), nunca nomes.
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs" / "usabilidade"

TASKS = {
    1: "Criar a conta e escolher o objetivo",
    2: "Montar uma ficha com um bi-set",
    3: "Registrar 3 séries, uma delas drop set",
    4: "Registrar uma caminhada",
    5: "Achar no Meu Corpo um músculo sem treino",
    6: "Registrar o peso de hoje",
    7: "Perguntar à IA sobre o último treino",
}
OUTCOMES = {"sim": "concluiu", "ajuda": "concluiu com ajuda", "nao": "não concluiu"}
SUS_ITEMS = 10
SUS_REFERENCE = 68  # média de referência do SUS (Sauro, 2011)


class DataError(ValueError):
    """Linha inválida numa planilha; a mensagem diz o arquivo e a linha."""


@dataclass(frozen=True)
class TaskResult:
    participant: str
    task: int
    outcome: str
    seconds: int
    errors: int
    seq: int | None


def sus_score(answers: list[int]) -> float:
    """Nota SUS (0 a 100) das 10 respostas de 1 a 5, na ordem do questionário.

    Itens ímpares (positivos) valem resposta - 1; pares (negativos), 5 - resposta.
    """
    if len(answers) != SUS_ITEMS:
        raise ValueError(f"O SUS tem {SUS_ITEMS} respostas, vieram {len(answers)}.")
    if any(a not in range(1, 6) for a in answers):
        raise ValueError("Cada resposta do SUS vai de 1 a 5.")
    total = sum(a - 1 if i % 2 == 0 else 5 - a for i, a in enumerate(answers))
    return total * 2.5


def _participant(value: str, where: str) -> str:
    code = value.strip().upper()
    if not (code.startswith("P") and code[1:].isdigit()):
        raise DataError(f"{where}: participante deve ser um código como P1, não {value!r}.")
    return code


def _int(value: str, where: str, field: str, low: int, high: int) -> int:
    try:
        number = int(value.strip())
    except ValueError:
        raise DataError(f"{where}: {field} deve ser um número inteiro, não {value!r}.") from None
    if not low <= number <= high:
        raise DataError(f"{where}: {field} deve ficar entre {low} e {high}.")
    return number


def read_tasks(path: Path) -> list[TaskResult]:
    results: list[TaskResult] = []
    seen: set[tuple[str, int]] = set()
    with path.open(encoding="utf-8", newline="") as f:
        for line, row in enumerate(csv.DictReader(f), start=2):
            where = f"{path.name}, linha {line}"
            participant = _participant(row["participante"], where)
            task = _int(row["tarefa"], where, "tarefa", 1, len(TASKS))
            outcome = row["concluiu"].strip().lower()
            if outcome not in OUTCOMES:
                raise DataError(f"{where}: concluiu deve ser sim, ajuda ou nao.")
            if (participant, task) in seen:
                raise DataError(f"{where}: {participant} já tem a tarefa {task}.")
            seen.add((participant, task))
            seq = row["seq"].strip()
            results.append(
                TaskResult(
                    participant=participant,
                    task=task,
                    outcome=outcome,
                    seconds=_int(row["tempo_s"], where, "tempo_s", 0, 3600),
                    errors=_int(row["erros"], where, "erros", 0, 99),
                    seq=_int(seq, where, "seq", 1, 7) if seq else None,
                )
            )
    return results


def read_sus(path: Path) -> dict[str, float]:
    scores: dict[str, float] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for line, row in enumerate(csv.DictReader(f), start=2):
            where = f"{path.name}, linha {line}"
            participant = _participant(row["participante"], where)
            if participant in scores:
                raise DataError(f"{where}: {participant} já respondeu o SUS.")
            answers = [_int(row[f"q{i}"], where, f"q{i}", 1, 5) for i in range(1, SUS_ITEMS + 1)]
            scores[participant] = sus_score(answers)
    return scores


def _num(value: float) -> str:
    return f"{value:.1f}".replace(".", ",").removesuffix(",0")


def _time(seconds: float) -> str:
    minutes, rest = divmod(round(seconds), 60)
    return f"{minutes}:{rest:02d}"


def render(results: list[TaskResult], sus: dict[str, float]) -> str:
    people = sorted({r.participant for r in results} | set(sus), key=lambda p: int(p[1:]))
    lines = ["# Testes de usabilidade — resultados", ""]
    if not people:
        lines.append("Ainda sem sessões registradas.")
        return "\n".join(lines) + "\n"

    lines += [
        f"Participantes: {len(people)} ({', '.join(people)}).",
        "",
        "## Por tarefa",
        "",
        "| Tarefa | Concluiu | Com ajuda | Não concluiu | Tempo (mediana) | Erros (média) "
        "| Facilidade (SEQ, de 1 a 7) |",
        "|---|---|---|---|---|---|---|",
    ]
    for task, name in TASKS.items():
        rows = [r for r in results if r.task == task]
        if not rows:
            lines.append(f"| {task}. {name} | — | — | — | — | — | — |")
            continue
        count = {key: sum(r.outcome == key for r in rows) for key in OUTCOMES}
        seqs = [r.seq for r in rows if r.seq is not None]
        lines.append(
            f"| {task}. {name} | {count['sim']}/{len(rows)} | {count['ajuda']} | {count['nao']} "
            f"| {_time(statistics.median(r.seconds for r in rows))} "
            f"| {_num(statistics.mean(r.errors for r in rows))} "
            f"| {_num(statistics.mean(seqs)) if seqs else '—'} |"
        )

    done = sum(r.outcome == "sim" for r in results)
    lines += [
        "",
        f"Conclusão sem ajuda: {done} de {len(results)} tentativas "
        f"({_num(100 * done / len(results))}%)."
        if results
        else "Nenhuma tarefa registrada.",
        "",
        "## SUS",
        "",
    ]
    if sus:
        mean = statistics.mean(sus.values())
        side = "acima" if mean > SUS_REFERENCE else "abaixo" if mean < SUS_REFERENCE else "igual"
        lines += [
            "| Participante | Nota |",
            "|---|---|",
            *(f"| {p} | {_num(sus[p])} |" for p in people if p in sus),
            "",
            f"Média: **{_num(mean)}** (de {_num(min(sus.values()))} a "
            f"{_num(max(sus.values()))}), {side} da referência de {SUS_REFERENCE}. "
            f"Com {len(sus)} pessoas, a média é indicativa, não estatística.",
        ]
    else:
        lines.append("Nenhum questionário SUS registrado.")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data", type=Path, default=DATA, help="pasta das planilhas")
    parser.add_argument("--out", type=Path, help="arquivo Markdown de saída")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # acentos certos no console do Windows
    try:
        report = render(read_tasks(args.data / "tarefas.csv"), read_sus(args.data / "sus.csv"))
    except (DataError, KeyError) as error:
        message = f"coluna ausente: {error}" if isinstance(error, KeyError) else error
        print(f"Erro: {message}", file=sys.stderr)
        return 1
    if args.out:
        args.out.write_text(report, encoding="utf-8", newline="\n")
        print(f"Relatório em {args.out}")
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
