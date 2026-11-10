"""Metodologia de estímulo v1 (3.5) e v2 (faixa "nenhuma" só para zero): a matriz de
casos do DATA_MODEL §6.

Casos obrigatórios: sem histórico; período sem sessões; série sem reps; exercício só com
músculos primários; com secundários; drop set com 3 segmentos (teto); rest-pause;
aquecimento ignorado; sessão excluída depois; 7 vs. 30 dias; mudança de versão.
"""

import uuid
from datetime import UTC, date, datetime

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update
from sqlalchemy.orm import Session

from app.modules.activities.models import Activity
from app.modules.analytics.models import METHODOLOGY_V1, METHODOLOGY_V2, StimulusMethodology
from app.modules.analytics.stimulus import MuscleRef, SetRow, band_for, muscle_stimulus
from app.modules.sessions.models import WorkoutSession
from tests.conftest import Clock
from tests.test_sessions import BASE as SESSIONS
from tests.test_sessions import PRANCHA, SUPINO, TRICEPS

API = "/api/v1"
ALL = ["chest", "triceps", "delts", "abs", "obliques"]
BENCH = uuid.uuid4()
PUSHDOWN = uuid.uuid4()
PLANK = uuid.uuid4()
MUSCLES = {
    BENCH: [
        MuscleRef("chest", "primary"),
        MuscleRef("triceps", "secondary"),
        MuscleRef("delts", "secondary"),
    ],
    PUSHDOWN: [MuscleRef("triceps", "primary")],
    PLANK: [MuscleRef("abs", "primary"), MuscleRef("obliques", "secondary")],
}
DAY = date(2026, 11, 1)


def s(exercise=BENCH, kind="working", parent=None, reps=8, load=60.0, day=DAY, **extra):
    return SetRow(
        id=uuid.uuid4(),
        day=day,
        exercise_id=exercise,
        kind=kind,
        parent_set_id=parent,
        reps=reps,
        load_kg=load,
        **extra,
    )


def run(sets: list[SetRow], days: int = 7, config: dict = METHODOLOGY_V1) -> dict:
    return {r.muscle_id: r for r in muscle_stimulus(sets, MUSCLES, ALL, config, days)}


# --- matriz de casos (função pura) ---


def test_no_history_gives_every_muscle_at_zero() -> None:
    rows = run([])
    assert set(rows) == set(ALL)
    assert all(
        (r.weighted_sets, r.weighted_sets_per_week, r.band, r.frequency, r.volume_load_kg)
        == (0, 0, "none", 0, 0)
        for r in rows.values()
    )


def test_primary_only_exercise() -> None:
    rows = run([s(PUSHDOWN), s(PUSHDOWN), s(PUSHDOWN)])
    assert rows["triceps"].weighted_sets == 3.0
    assert rows["chest"].weighted_sets == 0


def test_secondary_muscles_get_half() -> None:
    rows = run([s(), s()])
    assert (rows["chest"].weighted_sets, rows["triceps"].weighted_sets) == (2.0, 1.0)
    assert rows["delts"].weighted_sets == 1.0
    assert rows["chest"].exercises == {BENCH: 2.0}


def test_set_without_reps_does_not_count_but_timed_sets_do() -> None:
    rows = run([s(reps=None), s(PLANK, reps=None, load=None, duration_s=60, load_type="time")])
    assert rows["chest"].weighted_sets == 0
    assert (rows["abs"].weighted_sets, rows["obliques"].weighted_sets) == (1.0, 0.5)
    # Com a opção ligada, a série vazia passa a contar.
    config = {**METHODOLOGY_V1, "count_sets_without_reps": True}
    assert run([s(reps=None)], config=config)["chest"].weighted_sets == 1.0


def test_warmup_is_ignored_even_in_volume() -> None:
    rows = run([s(kind="warmup", reps=12, load=20), s()])
    assert rows["chest"].weighted_sets == 1.0
    assert rows["chest"].volume_load_kg == 8 * 60


def test_drop_set_with_three_segments_hits_the_cap() -> None:
    main = s(reps=8, load=60)
    drops = [s(kind="drop", parent=main.id, reps=6, load=load) for load in (50, 40, 30)]
    rows = run([main, *drops])
    # 1 + 0,5 + 0,5 = 2 (teto); o terceiro segmento não soma mais nada.
    assert rows["chest"].weighted_sets == 2.0
    assert rows["triceps"].weighted_sets == 1.0
    # O volume não tem teto: todos os segmentos contam.
    assert rows["chest"].volume_load_kg == 8 * 60 + 6 * (50 + 40 + 30)


def test_rest_pause_segments() -> None:
    main = s(reps=8)
    rows = run([main, s(kind="rest_pause", parent=main.id, reps=3)])
    assert rows["chest"].weighted_sets == 1.33
    two = run([main, *(s(kind="rest_pause", parent=main.id, reps=2) for _ in range(2))])
    assert two["chest"].weighted_sets == 1.66


def test_seven_versus_thirty_days_normalizes_per_week() -> None:
    sets = [s() for _ in range(12)]
    week, month = run(sets, days=7), run(sets, days=30)
    assert (week["chest"].weighted_sets_per_week, week["chest"].band) == (12.0, "high")
    # Mesmas 12 séries em 30 dias = 2,8 por semana: faixa baixa.
    assert (month["chest"].weighted_sets_per_week, month["chest"].band) == (2.8, "low")


@pytest.mark.parametrize(
    ("per_week", "band"),
    [(0, "none"), (0.49, "none"), (0.5, "low"), (5.99, "low"), (6, "mid"), (12, "high")],
)
def test_band_limits(per_week: float, band: str) -> None:
    assert band_for(per_week, METHODOLOGY_V1["bands_weekly_sets"]) == band


@pytest.mark.parametrize(
    ("per_week", "band"),
    [(0, "none"), (0.001, "low"), (0.47, "low"), (5.99, "low"), (6, "mid"), (12, "high")],
)
def test_v2_band_limits_regardless_of_key_order(per_week: float, band: str) -> None:
    bands = METHODOLOGY_V2["bands_weekly_sets"]
    # O JSONB devolve as chaves em outra ordem (por tamanho): high, low, mid, none.
    shuffled = {k: bands[k] for k in ("high", "low", "mid", "none")}
    assert band_for(per_week, bands) == band
    assert band_for(per_week, shuffled) == band


def test_v2_one_session_in_a_month_is_low_not_none() -> None:
    # 2 séries em 30 dias = 0,47 por semana: "nenhuma" na v1, "baixa" na v2.
    sets = [s(), s()]
    assert run(sets, days=30)["chest"].band == "none"
    v2 = run(sets, days=30, config=METHODOLOGY_V2)
    assert (v2["chest"].weighted_sets_per_week, v2["chest"].band) == (0.47, "low")
    assert v2["abs"].band == "none"


def test_band_uses_the_unrounded_rate() -> None:
    # Um segmento de rest-pause em secundário (0,165) em 366 dias arredonda para 0,0
    # por semana, mas houve estímulo: a faixa não pode ser "nenhuma".
    working = s(PLANK, reps=None, load=None, duration_s=60, kind="warmup")
    pause = s(PLANK, kind="rest_pause", parent=working.id, reps=3, load=None)
    rows = run([working, pause], days=366, config=METHODOLOGY_V2)
    assert rows["obliques"].weighted_sets > 0
    assert rows["obliques"].weighted_sets_per_week == 0.0
    assert rows["obliques"].band == "low"


def test_frequency_counts_distinct_days() -> None:
    rows = run([s(day=date(2026, 10, 27)), s(day=date(2026, 10, 27)), s(day=DAY)])
    assert rows["chest"].frequency == 2
    assert rows["abs"].frequency == 0


def test_volume_only_for_external_load_and_weighted_by_role() -> None:
    rows = run([s(load=100, reps=5), s(PLANK, reps=None, load=None, duration_s=60)])
    assert (rows["chest"].volume_load_kg, rows["triceps"].volume_load_kg) == (500, 250)
    assert rows["abs"].volume_load_kg == 0


def test_another_methodology_version_changes_the_result() -> None:
    v2 = {**METHODOLOGY_V1, "role_weights": {"primary": 1.0, "secondary": 0.25}}
    assert run([s()], config=v2)["triceps"].weighted_sets == 0.25


# --- API ---


def finished_session(client: TestClient, headers: dict, clock: Clock, *items) -> dict:
    """Treino livre concluído: items = (exercise_id, [sets])."""
    session = client.post(SESSIONS, headers=headers, json={}).json()
    for exercise_id, sets in items:
        session = client.post(
            f"{SESSIONS}/{session['id']}/exercises",
            headers=headers,
            json={"exercise_id": exercise_id},
        ).json()
        entry = session["exercises"][-1]["id"]
        parent = None
        for body in sets:
            if body.get("kind") in {"drop", "rest_pause"}:
                body = {**body, "parent_set_id": parent}
            response = client.post(
                f"{SESSIONS}/{session['id']}/exercises/{entry}/sets", headers=headers, json=body
            )
            assert response.status_code == 201, response.text
            if body.get("kind", "working") == "working":
                parent = response.json()["id"]
    clock.advance(minutes=45)
    response = client.post(f"{SESSIONS}/{session['id']}/finish", headers=headers, json={})
    assert response.status_code == 200, response.text
    return response.json()


def muscles(client: TestClient, headers: dict, **params) -> dict:
    response = client.get(f"{API}/analytics/muscles", headers=headers, params=params)
    assert response.status_code == 200, response.text
    return response.json()


WEEK = {"from": "2026-10-26", "to": "2026-11-01"}


def by_id(body: dict) -> dict:
    return {m["muscle_id"]: m for m in body["muscles"]}


def test_without_history_every_muscle_comes_back(client: TestClient, signup) -> None:
    body = muscles(client, signup(), **WEEK)

    assert body["methodology_version"] == "v2"
    assert body["period_days"] == 7
    assert "não diagnóstico" in body["notice"]
    assert body["bands"]["high"] == [12, None]
    assert body["bands"]["none"] == [0, 0]
    assert len(body["muscles"]) == 13
    assert body["muscles"][0]["muscle_id"] == "chest"  # ordem do catálogo
    assert {m["band"] for m in body["muscles"]} == {"none"}


def test_a_real_session(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    finished_session(
        client,
        headers,
        clock,
        (
            SUPINO,
            [
                {"kind": "warmup", "reps": 10, "load_kg": 20},
                {"reps": 8, "load_kg": 60},
                {"kind": "drop", "reps": 6, "load_kg": 40},
                {"reps": 8, "load_kg": 60},
            ],
        ),
        (TRICEPS, [{"reps": 12, "load_kg": 25}] * 3),
        (PRANCHA, [{"duration_s": 60}] * 2),
    )

    rows = by_id(muscles(client, headers, **WEEK))
    # Supino: 1,5 (série + drop) + 1 = 2,5 no peito; metade no tríceps e ombros.
    assert rows["chest"]["weighted_sets"] == 2.5
    assert rows["triceps"]["weighted_sets"] == 1.25 + 3
    assert rows["delts"]["weighted_sets"] == 1.25 + 1.0  # prancha: secundário
    assert rows["abs"]["weighted_sets"] == 2.0
    assert rows["chest"]["frequency"] == 1
    assert rows["chest"]["band"] == "low"
    assert rows["triceps"]["volume_load_kg"] == (480 + 240 + 480) / 2 + 3 * 300
    assert rows["quads"]["band"] == "none"
    assert rows["chest"]["name"] == "Peito"


def test_period_without_sessions_and_7_vs_30_days(client: TestClient, signup, clock: Clock) -> None:
    headers = signup()
    finished_session(client, headers, clock, (TRICEPS, [{"reps": 10, "load_kg": 20}] * 6))

    empty = by_id(muscles(client, headers, **{"from": "2026-10-01", "to": "2026-10-25"}))
    assert empty["triceps"]["weighted_sets"] == 0

    week = by_id(muscles(client, headers, **WEEK))["triceps"]
    month = by_id(muscles(client, headers, **{"from": "2026-10-03", "to": "2026-11-01"}))
    assert (week["weighted_sets_per_week"], week["band"]) == (6.0, "mid")
    assert (month["triceps"]["weighted_sets_per_week"], month["triceps"]["band"]) == (1.4, "low")


def test_deleted_session_leaves_the_map(
    client: TestClient, signup, clock: Clock, db: Session
) -> None:
    headers = signup()
    session = finished_session(client, headers, clock, (TRICEPS, [{"reps": 10}] * 3))
    assert by_id(muscles(client, headers, **WEEK))["triceps"]["weighted_sets"] == 3

    # Excluída depois (exclusão lógica da atividade, como em todo o histórico).
    activity_id = db.get(WorkoutSession, uuid.UUID(session["id"])).activity_id
    db.execute(
        update(Activity).where(Activity.id == activity_id).values(deleted_at=datetime.now(UTC))
    )
    db.flush()
    assert by_id(muscles(client, headers, **WEEK))["triceps"]["weighted_sets"] == 0


def test_unfinished_session_does_not_count(client: TestClient, signup) -> None:
    headers = signup()
    session = client.post(SESSIONS, headers=headers, json={}).json()
    session = client.post(
        f"{SESSIONS}/{session['id']}/exercises", headers=headers, json={"exercise_id": TRICEPS}
    ).json()
    entry = session["exercises"][-1]["id"]
    client.post(
        f"{SESSIONS}/{session['id']}/exercises/{entry}/sets", headers=headers, json={"reps": 10}
    )
    assert by_id(muscles(client, headers, **WEEK))["triceps"]["weighted_sets"] == 0


def test_new_methodology_version_is_used_and_reported(
    client: TestClient, signup, clock: Clock, db: Session
) -> None:
    headers = signup()
    finished_session(client, headers, clock, (SUPINO, [{"reps": 8, "load_kg": 60}] * 2))
    assert by_id(muscles(client, headers, **WEEK))["triceps"]["weighted_sets"] == 1.0

    db.execute(update(StimulusMethodology).values(active=False))
    db.add(
        StimulusMethodology(
            version="v2-teste",
            config={**METHODOLOGY_V1, "role_weights": {"primary": 1.0, "secondary": 0.25}},
            active=True,
            description="Teste: secundário vale 0,25.",
        )
    )
    db.flush()

    body = muscles(client, headers, **WEEK)
    assert body["methodology_version"] == "v2-teste"
    assert by_id(body)["triceps"]["weighted_sets"] == 0.5


def test_without_an_active_methodology_the_api_says_so(
    client: TestClient, signup, db: Session
) -> None:
    db.execute(update(StimulusMethodology).values(active=False))
    db.flush()
    response = client.get(f"{API}/analytics/muscles", headers=signup())
    assert response.status_code == 503
    assert response.json()["code"] == "methodology_unavailable"


# --- detalhe ---


def test_muscle_detail_with_exercises_loads_and_previous_period(
    client: TestClient, signup, clock: Clock
) -> None:
    headers = signup()
    # 01/11: tríceps na polia (primário) e supino (secundário).
    finished_session(
        client,
        headers,
        clock,
        (TRICEPS, [{"reps": 12, "load_kg": 20}, {"reps": 10, "load_kg": 25}]),
        (SUPINO, [{"reps": 8, "load_kg": 60}]),
    )
    # 08/11 (semana seguinte): só a polia, mais pesada.
    clock.advance(days=7)
    finished_session(client, headers, clock, (TRICEPS, [{"reps": 10, "load_kg": 30}] * 4))

    response = client.get(
        f"{API}/analytics/muscles/triceps",
        headers=headers,
        params={"from": "2026-11-02", "to": "2026-11-08", "compare": "previous"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["muscle"]["weighted_sets"] == 4.0
    assert body["exercises"] == [
        {
            "exercise_id": TRICEPS,
            "name": body["exercises"][0]["name"],
            "role": "primary",
            "weighted_sets": 4.0,
            "sets": 4,
            "best_load_kg": 30.0,
        }
    ]
    assert body["previous"] == {
        "from_date": "2026-10-26",
        "to_date": "2026-11-01",
        "weighted_sets_per_week": 2.5,
        "frequency": 1,
        "band": "low",
        "difference": 1.5,
        "percent": 60.0,
    }

    two_weeks = client.get(
        f"{API}/analytics/muscles/triceps",
        headers=headers,
        params={"from": "2026-10-26", "to": "2026-11-08"},
    ).json()
    assert [(e["exercise_id"], e["role"]) for e in two_weeks["exercises"]] == [
        (TRICEPS, "primary"),
        (SUPINO, "secondary"),
    ]
    # Por dia; no mesmo dia, um ponto por exercício.
    assert sorted((p["day"], p["best_load_kg"]) for p in two_weeks["loads"]) == [
        ("2026-11-01", 25.0),
        ("2026-11-01", 60.0),
        ("2026-11-08", 30.0),
    ]
    assert two_weeks["previous"] is None


def test_unknown_muscle_is_404(client: TestClient, signup) -> None:
    response = client.get(f"{API}/analytics/muscles/wings", headers=signup())
    assert response.status_code == 404
    assert response.json()["detail"] == "Músculo não encontrado."
