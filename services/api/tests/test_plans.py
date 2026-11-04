"""Planos progressivos (3.3): templates versionados, geração, ajustes, vínculo com atividades."""

import logging
import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.modules.plans import templates
from tests.test_activities import RUN

API = "/api/v1"
PLANS = f"{API}/training-plans"
MON_WED_FRI = [0, 2, 4]


def ago(**delta: float) -> str:
    return (datetime.now(UTC) - timedelta(**delta)).isoformat()


def ok(response, status: int = 200) -> dict:
    assert response.status_code == status, response.text
    return response.json()


def start(client: TestClient, headers: dict, kind: str = "run_5k", **changes) -> dict:
    body = {"kind": kind, "weekdays": MON_WED_FRI, **changes}
    return ok(client.post(PLANS, headers=headers, json=body), 201)


def activity(client: TestClient, headers: dict, **changes) -> str:
    body = {**RUN, "started_at": ago(hours=2), **changes}
    return ok(client.post(f"{API}/activities", headers=headers, json=body), 201)["id"]


def link(client: TestClient, headers: dict, plan: dict, session: dict, activity_id: str):
    return client.put(
        f"{PLANS}/{plan['id']}/sessions/{session['id']}/activity",
        headers=headers,
        json={"activity_id": activity_id},
    )


def field_errors(response) -> list[str]:
    return [e["field"] for e in response.json().get("errors", [])]


def with_limitations(client: TestClient, headers: dict, *tags: str) -> None:
    ok(client.put(f"{API}/me/consents/health_data", headers=headers))
    ok(client.patch(f"{API}/me", headers=headers, json={"limitation_tags": list(tags)}))


@pytest.fixture(autouse=True)
def _yesterday(plans_from_yesterday):
    return plans_from_yesterday


# --- templates ---


def test_templates_are_versioned_and_listed(client: TestClient, signup) -> None:
    body = ok(client.get(f"{API}/training-plan-templates", headers=signup()))

    assert [(t["kind"], t["version"], t["weeks"]) for t in body] == [
        ("walk_habit", 1, 8),
        ("run_5k", 1, 9),
        ("run_10k", 1, 8),
    ]
    assert [t["modality"] for t in body] == ["walk", "run", "run"]
    assert all(t["sessions_per_week"] == 3 and t["adaptations"] == [] for t in body)
    assert body[1]["prerequisite"] == "Para quem já caminha 30 minutos sem desconforto."


def test_ten_k_suggests_the_5k_plan_until_there_is_a_5k_run(client: TestClient, signup) -> None:
    headers = signup()

    def note() -> str | None:
        body = ok(client.get(f"{API}/training-plan-templates", headers=headers))
        return {t["kind"]: t["note"] for t in body}["run_10k"]

    assert "Primeiros 5 km" in note()
    activity(client, headers, distance_m=3000, duration_s=1200)  # curta: ainda não
    assert note() is not None
    # 30 min sem chegar a 5 km (uma sessão do plano de 5 km, por exemplo): ainda não.
    activity(client, headers, distance_m=3600, duration_s=1800)
    assert note() is not None
    activity(client, headers, distance_m=5000, duration_s=1900)
    assert note() is None


def test_templates_require_login(client: TestClient) -> None:
    assert client.get(f"{API}/training-plan-templates").status_code == 401


# --- geração ---


def test_start_a_5k_plan(client: TestClient, signup, plans_from_yesterday) -> None:
    headers = signup()
    response = client.post(PLANS, headers=headers, json={"kind": "run_5k", "weekdays": [4, 0, 2]})

    assert response.status_code == 201, response.text
    plan = response.json()
    assert response.headers["location"] == f"{PLANS}/{plan['id']}"
    assert plan["title"] == "Primeiros 5 km"
    assert plan["status"] == "active"
    assert plan["weekdays"] == [0, 2, 4]
    assert (plan["weeks"], plan["total_sessions"], plan["completed_sessions"]) == (9, 27, 0)
    assert plan["current_week"] == 1
    sessions = plan["sessions"]
    assert plan["next_session_id"] == sessions[0]["id"]
    assert [s["position"] for s in sessions] == list(range(1, 28))
    assert [(s["week"], s["day_index"]) for s in sessions[:4]] == [(1, 1), (1, 2), (1, 3), (2, 1)]

    first = sessions[0]
    assert first["summary"] == (
        "5 min caminhando · 8x (1 min correndo + 1:30 caminhando) · 5 min caminhando"
    )
    assert first["total_s"] == 5 * 60 + 8 * 150 + 5 * 60
    assert first["blocks"][1]["repeat"] == 8
    assert sessions[-1]["summary"] == "5 min caminhando · 5 km correndo · 5 min caminhando"

    # Datas sugeridas: os dias escolhidos, em ordem, a partir do início.
    dates = [date.fromisoformat(s["scheduled_date"]) for s in sessions]
    start_date = date.fromisoformat(plan["start_date"])
    assert dates == sorted(dates) and len(set(dates)) == 27
    assert all(d.weekday() in (0, 2, 4) for d in dates)
    assert start_date <= dates[0] < start_date + timedelta(days=7)


def test_walk_and_10k_plans(client: TestClient, signup) -> None:
    walk = start(client, signup(), "walk_habit", weekdays=[0, 1, 2])  # seguidos: ok
    assert (walk["weeks"], walk["total_sessions"]) == (8, 24)
    assert walk["sessions"][0]["summary"] == "20 min caminhando em ritmo firme"

    ten = start(client, signup("bia@exemplo.com", "Bia"), "run_10k")
    assert (ten["weeks"], ten["total_sessions"]) == (8, 24)
    assert ten["sessions"][-1]["summary"] == "5 min caminhando · 10 km correndo · 5 min caminhando"


@pytest.mark.parametrize(
    ("kind", "weekdays", "message"),
    [
        ("run_5k", [0, 2], "Escolha 3 dias diferentes."),
        ("run_5k", [0, 2, 2], "Escolha 3 dias diferentes."),
        ("run_5k", [0, 2, 4, 6], "Escolha 3 dias diferentes."),
        ("run_5k", [0, 1, 3], "Na corrida, deixe um dia de descanso entre as sessões."),
        ("run_10k", [6, 0, 3], "Na corrida, deixe um dia de descanso entre as sessões."),
        ("walk_habit", [0, 7, 2], None),
    ],
)
def test_weekdays_rules(
    client: TestClient, signup, kind: str, weekdays: list[int], message: str | None
) -> None:
    response = client.post(PLANS, headers=signup(), json={"kind": kind, "weekdays": weekdays})

    assert response.status_code == 422, response.text
    assert field_errors(response)[0].startswith("weekdays")
    if message:
        assert response.json()["errors"][0]["message"] == message


def test_start_date_window(client: TestClient, signup, plans_from_yesterday) -> None:
    headers = signup()
    today = date.today()
    for day in (today - timedelta(days=3), today + timedelta(days=40)):
        response = client.post(
            PLANS,
            headers=headers,
            json={"kind": "run_5k", "weekdays": MON_WED_FRI, "start_date": day.isoformat()},
        )
        assert response.status_code == 422
        assert field_errors(response) == ["start_date"]

    later = today + timedelta(days=10)
    plan = start(client, headers, start_date=later.isoformat())
    assert plan["start_date"] == later.isoformat()
    assert date.fromisoformat(plan["sessions"][0]["scheduled_date"]) >= later


def test_unknown_kind_and_extra_fields_are_rejected(client: TestClient, signup) -> None:
    headers = signup()
    for body in (
        {"kind": "marathon", "weekdays": MON_WED_FRI},
        {"kind": "run_5k", "weekdays": MON_WED_FRI, "user_id": str(uuid.uuid4())},
    ):
        assert client.post(PLANS, headers=headers, json=body).status_code == 422


def test_one_active_plan_at_a_time(client: TestClient, signup) -> None:
    headers = signup()
    first = start(client, headers)

    response = client.post(PLANS, headers=headers, json={"kind": "walk_habit", "weekdays": [1]})
    assert response.status_code == 422  # validação antes do conflito
    response = client.post(
        PLANS, headers=headers, json={"kind": "walk_habit", "weekdays": [0, 1, 2]}
    )
    assert response.status_code == 409
    assert response.json()["code"] == "plan_in_progress"
    assert response.json()["errors"][0]["message"] == first["id"]

    ended = ok(client.post(f"{PLANS}/{first['id']}/end", headers=headers))
    assert ended["status"] == "ended" and ended["ended_at"] is not None
    assert ended["next_session_id"] is None
    second = start(client, headers, "walk_habit")

    plans = ok(client.get(PLANS, headers=headers))
    assert [p["id"] for p in plans] == [second["id"], first["id"]]
    assert "sessions" not in plans[0]


def test_plan_keeps_its_copy_when_the_template_changes(
    client: TestClient, signup, monkeypatch: pytest.MonkeyPatch
) -> None:
    headers = signup()
    plan = start(client, headers)
    changed = templates.PlanTemplate(
        **{
            **templates.TEMPLATES["run_5k"].__dict__,
            "version": 2,
            "weeks": (templates.TEMPLATES["run_5k"].weeks[-1],) * 9,
        }
    )
    monkeypatch.setitem(templates.TEMPLATES, "run_5k", changed)

    again = ok(client.get(f"{PLANS}/{plan['id']}", headers=headers))
    assert again["template_version"] == 1
    assert again["sessions"] == plan["sessions"]


# --- ajustes para a pessoa ---


def test_joint_limitation_repeats_weeks_in_running_plans(client: TestClient, signup) -> None:
    headers = signup()
    with_limitations(client, headers, "knee")

    offered = {
        t["kind"]: t for t in ok(client.get(f"{API}/training-plan-templates", headers=headers))
    }
    assert offered["run_5k"]["weeks"] == 13  # semanas 2, 4, 6 e 8 se repetem
    assert offered["run_10k"]["weeks"] == 11  # 2, 4 e 6 (a última não)
    assert offered["walk_habit"]["weeks"] == 8
    assert offered["walk_habit"]["adaptations"] == []
    assert "Algumas semanas se repetem" in offered["run_5k"]["adaptations"][0]

    plan = start(client, headers)
    assert (plan["weeks"], plan["total_sessions"]) == (13, 39)
    weeks = {s["week"]: s["summary"] for s in plan["sessions"] if s["day_index"] == 1}
    assert weeks[2] == weeks[3]  # a semana 2 do template, duas vezes
    assert weeks[3] != weeks[4]
    assert plan["adaptations"] == offered["run_5k"]["adaptations"]


def test_heart_condition_advises_a_medical_check(client: TestClient, signup) -> None:
    headers = signup()
    with_limitations(client, headers, "hypertension_reported")

    plan = start(client, headers, "walk_habit")
    assert plan["weeks"] == 8
    assert len(plan["adaptations"]) == 1
    assert "converse com seu médico" in plan["adaptations"][0]


def test_revoking_health_consent_removes_health_based_adaptations(
    client: TestClient, signup
) -> None:
    headers = signup()
    with_limitations(client, headers, "ankle", "cardiac_condition_reported")
    plan = start(client, headers)
    assert len(plan["adaptations"]) == 2

    assert client.delete(f"{API}/me/consents/health_data", headers=headers).status_code == 204

    again = ok(client.get(f"{PLANS}/{plan['id']}", headers=headers))
    assert again["adaptations"] == []
    assert again["total_sessions"] == plan["total_sessions"]  # a prescrição fica
    offered = ok(client.get(f"{API}/training-plan-templates", headers=headers))
    assert {t["weeks"] for t in offered if t["kind"] == "run_5k"} == {9}


def test_logs_do_not_carry_limitations(
    client: TestClient, signup, caplog: pytest.LogCaptureFixture
) -> None:
    headers = signup()
    with_limitations(client, headers, "knee")
    caplog.set_level(logging.DEBUG)

    start(client, headers)

    records = [r for r in caplog.records if r.getMessage() == "plan_created"]
    assert len(records) == 1
    assert not {"joint_care", "adapted_for", "limitation_tags"} & set(records[0].__dict__)
    assert "knee" not in caplog.text and "joint" not in caplog.text


# --- sessões feitas ---


def test_link_an_activity_to_a_session(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers)
    first, second = plan["sessions"][:2]
    run_id = activity(client, headers)

    done = ok(link(client, headers, plan, first, run_id))
    assert done["sessions"][0]["completed_activity_id"] == run_id
    assert done["sessions"][0]["completed_at"] is not None
    assert done["completed_sessions"] == 1
    assert done["next_session_id"] == second["id"]

    # De novo com a mesma: nada muda.
    again = ok(link(client, headers, plan, first, run_id))
    assert again["sessions"][0]["completed_at"] == done["sessions"][0]["completed_at"]

    # Em qualquer ordem: a próxima continua sendo a primeira não feita.
    third = ok(link(client, headers, plan, plan["sessions"][2], activity(client, headers)))
    assert third["next_session_id"] == second["id"]
    # A semana atual também vem no resumo (a lista não traz as sessões).
    for index in range(3, 5):
        ok(link(client, headers, plan, plan["sessions"][index], activity(client, headers)))
    ok(link(client, headers, plan, second, activity(client, headers)))
    summary = ok(client.get(PLANS, headers=headers))[0]
    assert (summary["current_week"], summary["completed_sessions"]) == (2, 5)
    for session in (second, plan["sessions"][3], plan["sessions"][4]):
        ok(
            client.delete(
                f"{PLANS}/{plan['id']}/sessions/{session['id']}/activity", headers=headers
            )
        )

    undone = ok(
        client.delete(f"{PLANS}/{plan['id']}/sessions/{first['id']}/activity", headers=headers)
    )
    assert undone["sessions"][0]["completed_activity_id"] is None
    assert undone["completed_sessions"] == 1
    assert undone["next_session_id"] == first["id"]
    # A atividade continua lá.
    assert client.get(f"{API}/activities/{run_id}", headers=headers).status_code == 200


@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"modality": "walk"}, "Esta sessão pede uma corrida."),
        ({"modality": "cycle"}, "Esta sessão pede uma corrida."),
        ({"started_at": ago(days=3)}, "A atividade é de antes do início do plano."),
    ],
)
def test_activity_must_fit_the_session(
    client: TestClient, signup, changes: dict, message: str
) -> None:
    headers = signup()
    plan = start(client, headers)
    response = link(
        client, headers, plan, plan["sessions"][0], activity(client, headers, **changes)
    )

    assert response.status_code == 422
    assert response.json()["errors"] == [{"field": "activity_id", "message": message}]


def test_walking_plan_accepts_walks_and_runs(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers, "walk_habit")
    for index, modality in enumerate(("walk", "run")):
        session = plan["sessions"][index]
        ok(link(client, headers, plan, session, activity(client, headers, modality=modality)))


def test_one_activity_counts_for_one_session(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers)
    run_id = activity(client, headers)
    ok(link(client, headers, plan, plan["sessions"][0], run_id))

    response = link(client, headers, plan, plan["sessions"][1], run_id)
    assert response.status_code == 422
    assert response.json()["errors"][0]["message"] == "Esta atividade já conta para outra sessão."


def test_unknown_or_deleted_activity(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers)
    first = plan["sessions"][0]

    response = link(client, headers, plan, first, str(uuid.uuid4()))
    assert response.status_code == 422
    assert field_errors(response) == ["activity_id"]

    run_id = activity(client, headers)
    ok(link(client, headers, plan, first, run_id))
    assert client.delete(f"{API}/activities/{run_id}", headers=headers).status_code == 204

    # Excluir a atividade desfaz a sessão; uma excluída não pode ser ligada.
    again = ok(client.get(f"{PLANS}/{plan['id']}", headers=headers))
    assert again["sessions"][0]["completed_activity_id"] is None
    assert again["completed_sessions"] == 0
    assert again["next_session_id"] == first["id"]
    assert link(client, headers, plan, first, run_id).status_code == 422


def test_finishing_every_session_completes_the_plan(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers, "walk_habit")
    sessions = plan["sessions"]

    for session in sessions[:-1]:
        current = ok(
            link(client, headers, plan, session, activity(client, headers, modality="walk"))
        )
        assert current["status"] == "active"
    last = ok(link(client, headers, plan, sessions[-1], activity(client, headers, modality="walk")))

    assert last["status"] == "completed"
    assert last["ended_at"] is not None
    assert last["next_session_id"] is None
    assert last["completed_sessions"] == 24
    # Concluído não se altera, e outro pode começar.
    response = client.delete(
        f"{PLANS}/{plan['id']}/sessions/{sessions[0]['id']}/activity", headers=headers
    )
    assert response.status_code == 409
    assert client.post(f"{PLANS}/{plan['id']}/end", headers=headers).status_code == 409
    start(client, headers)


def test_ended_plan_is_read_only(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers)
    ok(client.post(f"{PLANS}/{plan['id']}/end", headers=headers))

    response = link(client, headers, plan, plan["sessions"][0], activity(client, headers))
    assert response.status_code == 409
    assert response.json()["code"] == "plan_closed"
    assert client.post(f"{PLANS}/{plan['id']}/end", headers=headers).status_code == 409


def test_missing_plan_or_session_is_404(client: TestClient, signup) -> None:
    headers = signup()
    plan = start(client, headers)
    other = start(client, signup("bia@exemplo.com", "Bia"))
    run_id = activity(client, headers)

    assert client.get(f"{PLANS}/{uuid.uuid4()}", headers=headers).status_code == 404
    # Sessão de outro plano (de outra pessoa) no caminho do próprio plano.
    response = link(client, headers, plan, other["sessions"][0], run_id)
    assert response.status_code == 404
    assert response.json()["detail"] == "Sessão não encontrada."
