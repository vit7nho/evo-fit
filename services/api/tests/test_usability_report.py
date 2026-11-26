"""Testes do resumo dos testes de usabilidade (scripts/usability_report.py, etapa 5.7).

O script fica na raiz do repositório (não é parte da API); os testes moram aqui para rodar
com o mesmo pytest e o mesmo ruff de sempre.
"""

import importlib.util
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "usability_report.py"
_spec = importlib.util.spec_from_file_location("usability_report", SCRIPT)
assert _spec is not None and _spec.loader is not None
report = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = report  # as dataclasses procuram o módulo aqui
_spec.loader.exec_module(report)

TASK_HEADER = "participante,tarefa,concluiu,tempo_s,erros,seq,observacao\n"
SUS_HEADER = "participante," + ",".join(f"q{i}" for i in range(1, 11)) + "\n"


def _write(folder: Path, tasks: str = "", sus: str = "") -> Path:
    (folder / "tarefas.csv").write_text(TASK_HEADER + tasks, encoding="utf-8")
    (folder / "sus.csv").write_text(SUS_HEADER + sus, encoding="utf-8")
    return folder


@pytest.mark.parametrize(
    ("answers", "expected"),
    [
        ([5, 1, 5, 1, 5, 1, 5, 1, 5, 1], 100.0),  # o melhor possível
        ([1, 5, 1, 5, 1, 5, 1, 5, 1, 5], 0.0),  # o pior possível
        ([3] * 10, 50.0),  # neutro em tudo
        ([4, 2, 4, 1, 4, 2, 5, 1, 4, 2], 82.5),  # conta feita à mão: (3+3+3+4+3+3+4+4+3+3)·2,5
    ],
)
def test_sus_score_follows_the_standard_formula(answers, expected):
    assert report.sus_score(answers) == expected


@pytest.mark.parametrize("answers", [[3] * 9, [3] * 11, [0] + [3] * 9, [6] + [3] * 9])
def test_sus_score_rejects_incomplete_or_out_of_range(answers):
    with pytest.raises(ValueError):
        report.sus_score(answers)


def test_empty_spreadsheets_say_there_are_no_sessions(tmp_path):
    folder = _write(tmp_path)
    text = report.render(
        report.read_tasks(folder / "tarefas.csv"), report.read_sus(folder / "sus.csv")
    )
    assert "Ainda sem sessões registradas." in text


def test_report_summarises_tasks_and_sus(tmp_path):
    folder = _write(
        tmp_path,
        tasks=(
            "P1,1,sim,120,0,7,\n"
            "P2,1,sim,180,1,6,errou a senha\n"
            "P3,1,ajuda,300,2,4,\n"
            "P1,3,nao,240,3,2,não achou o drop set\n"
        ),
        sus="P1,4,2,4,1,4,2,5,1,4,2\nP2,3,3,3,3,3,3,3,3,3,3\n",
    )
    out = tmp_path / "relatorio.md"
    assert report.main(["--data", str(folder), "--out", str(out)]) == 0
    text = out.read_text(encoding="utf-8")

    assert "Participantes: 3 (P1, P2, P3)." in text
    # Tarefa 1: 2 de 3 sem ajuda, mediana de 180 s, 1 erro em média, SEQ (7+6+4)/3.
    assert "| 1. Criar a conta e escolher o objetivo | 2/3 | 1 | 0 | 3:00 | 1 | 5,7 |" in text
    assert "| 3. Registrar 3 séries, uma delas drop set | 0/1 | 0 | 1 | 4:00 | 3 | 2 |" in text
    assert "| 2. Montar uma ficha com um bi-set | — | — | — | — | — | — |" in text
    assert "Conclusão sem ajuda: 2 de 4 tentativas (50%)." in text
    assert "| P1 | 82,5 |" in text
    assert "| P2 | 50 |" in text
    assert "Média: **66,2** (de 50 a 82,5), abaixo da referência de 68." in text
    # O texto livre da observação não vai para o relatório.
    assert "errou a senha" not in text


@pytest.mark.parametrize(
    ("tasks", "sus", "message"),
    [
        ("Maria,1,sim,60,0,7,\n", "", "código como P1"),
        ("P1,8,sim,60,0,7,\n", "", "tarefa deve ficar entre 1 e 7"),
        ("P1,1,talvez,60,0,7,\n", "", "sim, ajuda ou nao"),
        ("P1,1,sim,60,0,9,\n", "", "seq deve ficar entre 1 e 7"),
        ("P1,1,sim,1min,0,7,\n", "", "tempo_s deve ser um número inteiro"),
        ("P1,1,sim,60,0,7,\nP1,1,sim,70,0,7,\n", "", "P1 já tem a tarefa 1"),
        ("", "P1,3,3,3,3,3,3,3,3,3,6\n", "q10 deve ficar entre 1 e 5"),
        ("", "P1,3,3,3,3,3,3,3,3,3,3\nP1,3,3,3,3,3,3,3,3,3,3\n", "P1 já respondeu"),
    ],
)
def test_invalid_rows_point_to_the_line(tmp_path, capsys, tasks, sus, message):
    folder = _write(tmp_path, tasks=tasks, sus=sus)
    assert report.main(["--data", str(folder)]) == 1
    error = capsys.readouterr().err
    assert message in error
    assert "linha" in error


def test_missing_column_is_reported(tmp_path, capsys):
    (tmp_path / "tarefas.csv").write_text("participante,tarefa\nP1,1\n", encoding="utf-8")
    (tmp_path / "sus.csv").write_text(SUS_HEADER, encoding="utf-8")
    assert report.main(["--data", str(tmp_path)]) == 1
    assert "coluna ausente" in capsys.readouterr().err


def test_repository_spreadsheets_are_valid_and_anonymous():
    """As planilhas versionadas leem sem erro e só têm códigos de participante."""
    tasks = report.read_tasks(report.DATA / "tarefas.csv")
    sus = report.read_sus(report.DATA / "sus.csv")
    assert all(r.participant.startswith("P") for r in tasks)
    assert all(p.startswith("P") for p in sus)
