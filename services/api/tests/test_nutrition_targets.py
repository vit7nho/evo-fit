"""Metas nutricionais (5.2, ADR-059): limites de segurança, histórico por dia,
o resumo de cada dia com a meta que valia, consentimento e privacidade."""

from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.modules.nutrition import service
from tests.test_analytics import ok
from tests.test_nutrition import ARROZ, FRANGO, food, meal

API = "/api/v1"
TARGETS = f"{API}/nutrition/targets"
FULL = {"kcal": 2000, "protein_g": 150, "carbs_g": 200, "fat_g": 67}


@pytest.fixture
def ana(signup, client: TestClient) -> dict:
    headers = signup("ana@exemplo.com", "Ana")
    ok(client.put(f"{API}/me/consents/health_data", headers=headers))
    return headers


@pytest.fixture
def bia(signup) -> dict:
    return signup("bia@exemplo.com", "Bia")


@pytest.fixture
def on_day(monkeypatch: pytest.MonkeyPatch):
    """Muda o "hoje" em que a meta passa a valer."""

    def set_day(day: date) -> None:
        monkeypatch.setattr(service, "_today", lambda user: day)

    return set_day


def errors(response) -> dict[str, str]:
    assert response.status_code == 422, response.text
    return {e["field"]: e["message"] for e in response.json()["errors"]}


def test_targets_need_the_health_consent(client: TestClient, bia: dict) -> None:
    empty = ok(client.get(TARGETS, headers=bia))
    assert (empty["current"], empty["history"]) == (None, [])
    assert empty["limits"]["kcal"] == {"min": 1200, "max": 5000}
    assert empty["limits"]["kcal_allowed"] is True

    response = client.put(TARGETS, headers=bia, json={"kcal": 2000})
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"


def test_setting_and_reading_the_targets(client: TestClient, ana: dict) -> None:
    saved = ok(client.put(TARGETS, headers=ana, json=FULL))
    current = saved["current"]
    assert {k: current[k] for k in FULL} == FULL
    # 150 x 4 + 200 x 4 + 67 x 9
    assert current["macros_kcal"] == 2003
    assert len(saved["history"]) == 1
    assert ok(client.get(TARGETS, headers=ana)) == saved

    # Só a proteína: as outras ficam sem meta.
    only = ok(client.put(TARGETS, headers=ana, json={"protein_g": 120}))["current"]
    assert (only["kcal"], only["protein_g"], only["macros_kcal"]) == (None, 120, 480)


@pytest.mark.parametrize(
    ("body", "field", "text"),
    [
        ({"kcal": 1000}, "kcal", "Abaixo de 1.200 kcal"),
        ({"kcal": 6000}, "kcal", "Acima de 5.000 kcal"),
        ({"protein_g": 400}, "protein_g", "entre 20 e 300 g"),
        ({"fat_g": 10}, "fat_g", "entre 20 e 250 g"),
        ({"carbs_g": 900}, "carbs_g", "entre 20 e 800 g"),
        # 150 x 4 + 400 x 4 + 80 x 9 = 2920 kcal, acima de 2000 + 15 %.
        ({"kcal": 2000, "protein_g": 150, "carbs_g": 400, "fat_g": 80}, "__root__", "2.920 kcal"),
        # Só a proteína já passa da meta de calorias.
        ({"kcal": 1300, "protein_g": 300, "carbs_g": 200}, "__root__", "acima da meta"),
        # Completos e bem abaixo: 100 x 4 + 200 x 4 + 50 x 9 = 1650 kcal para 3000.
        ({"kcal": 3000, "protein_g": 100, "carbs_g": 200, "fat_g": 50}, "__root__", "abaixo"),
    ],
)
def test_unsafe_targets_are_rejected(
    client: TestClient, ana: dict, body: dict, field: str, text: str
) -> None:
    found = errors(client.put(TARGETS, headers=ana, json=body))
    assert text in found[field]
    assert ok(client.get(TARGETS, headers=ana))["current"] is None


def test_partial_macros_below_the_calories_are_fine(client: TestClient, ana: dict) -> None:
    # Sem a gordura, a soma fica abaixo das calorias: é o espaço da meta que falta.
    saved = ok(client.put(TARGETS, headers=ana, json={"kcal": 2500, "protein_g": 140}))
    assert saved["current"]["macros_kcal"] == 560


def test_the_minimum_follows_the_sex_for_calculations(client: TestClient, ana: dict) -> None:
    ok(client.patch(f"{API}/me", headers=ana, json={"sex_for_calculations": "male"}))
    assert ok(client.get(TARGETS, headers=ana))["limits"]["kcal"]["min"] == 1500
    assert (
        "Abaixo de 1.500 kcal"
        in errors(client.put(TARGETS, headers=ana, json={"kcal": 1400}))["kcal"]
    )
    ok(client.patch(f"{API}/me", headers=ana, json={"sex_for_calculations": "female"}))
    ok(client.put(TARGETS, headers=ana, json={"kcal": 1400}))


def test_no_calorie_target_for_minors(client: TestClient, ana: dict) -> None:
    year = datetime.now(UTC).year - 15
    ok(client.patch(f"{API}/me", headers=ana, json={"birth_year": year}))
    assert ok(client.get(TARGETS, headers=ana))["limits"]["kcal_allowed"] is False
    assert (
        "menores de 18 anos"
        in errors(client.put(TARGETS, headers=ana, json={"kcal": 2000}))["kcal"]
    )
    # A proteína pode.
    ok(client.put(TARGETS, headers=ana, json={"protein_g": 90}))


def test_history_one_target_per_day(client: TestClient, ana: dict, on_day) -> None:
    real_today = datetime.now(UTC).date()
    first, second = real_today - timedelta(days=4), real_today - timedelta(days=2)
    on_day(first)
    ok(client.put(TARGETS, headers=ana, json={"kcal": 2000}))
    on_day(second)
    ok(client.put(TARGETS, headers=ana, json={"kcal": 2200}))
    # Outra mudança no mesmo dia substitui a do dia.
    saved = ok(client.put(TARGETS, headers=ana, json={"kcal": 2300}))
    assert [(t["valid_from"], t["kcal"]) for t in saved["history"]] == [
        (second.isoformat(), 2300),
        (first.isoformat(), 2000),
    ]

    def daily(day: date) -> dict | None:
        return ok(client.get(f"{API}/nutrition/daily?date={day}", headers=ana))["targets"]

    assert daily(first - timedelta(days=1)) is None
    assert daily(first + timedelta(days=1))["kcal"] == 2000
    assert daily(second)["kcal"] == 2300

    # Tirar as metas vale a partir de hoje; os dias anteriores continuam com a meta.
    on_day(real_today - timedelta(days=1))
    cleared = ok(client.put(TARGETS, headers=ana, json={}))
    assert cleared["current"] is None
    assert daily(second)["kcal"] == 2300
    assert daily(real_today) is None


def test_summary_compares_each_day_with_its_target(client: TestClient, ana: dict, on_day) -> None:
    arroz, frango = food(client, ana, ARROZ), food(client, ana, FRANGO)
    on_day(date(2026, 10, 31))
    ok(client.put(TARGETS, headers=ana, json={"kcal": 1800, "protein_g": 120}))
    # 12h30 em São Paulo, 01/11; e 22h de 02/11 (01h do dia 3 em UTC).
    meal(client, ana, [{"food_id": arroz["id"], "quantity_g": 200}])
    meal(
        client,
        ana,
        [{"food_id": frango["id"], "quantity_g": 100}],
        eaten_at="2026-11-03T01:00:00Z",
        meal_type="dinner",
    )

    summary = ok(client.get(f"{API}/nutrition/summary?from=2026-10-30&to=2026-11-03", headers=ana))
    days = {d["date"]: d for d in summary["days"]}
    assert len(days) == 5
    assert days["2026-10-30"]["targets"] is None
    assert days["2026-10-31"]["targets"]["kcal"] == 1800
    assert (days["2026-11-01"]["meals"], days["2026-11-01"]["totals"]["kcal"]) == (1, 256)
    assert (days["2026-11-02"]["meals"], days["2026-11-02"]["totals"]["protein_g"]) == (1, 32)
    assert days["2026-11-03"]["meals"] == 0
    # Média só dos dias com refeição: (256 + 159) / 2.
    assert summary["logged_days"] == 2
    assert summary["average"]["kcal"] == 207.5
    # Só o arroz tem fibra registrada: a média da fibra é dele.
    assert summary["average"]["fiber_g"] == 3.2


@pytest.mark.parametrize(
    ("query", "field"),
    [("from=2026-11-05&to=2026-11-01", "from"), ("from=2026-01-01&to=2026-11-01", "to")],
)
def test_summary_range_is_checked(client: TestClient, ana: dict, query: str, field: str) -> None:
    assert field in errors(client.get(f"{API}/nutrition/summary?{query}", headers=ana))


def test_summary_defaults_to_the_last_seven_days(client: TestClient, ana: dict) -> None:
    summary = ok(client.get(f"{API}/nutrition/summary", headers=ana))
    assert len(summary["days"]) == 7
    assert (summary["logged_days"], summary["average"]) == (0, None)


def test_targets_are_private(client: TestClient, ana: dict, bia: dict) -> None:
    ok(client.put(TARGETS, headers=ana, json=FULL))
    assert ok(client.get(TARGETS, headers=bia))["current"] is None
    days = ok(client.get(f"{API}/nutrition/summary", headers=bia))["days"]
    assert all(d["targets"] is None for d in days)


def test_revoking_health_data_deletes_the_targets(client: TestClient, ana: dict) -> None:
    ok(client.put(TARGETS, headers=ana, json=FULL))
    response = client.delete(f"{API}/me/consents/health_data", headers=ana)
    assert response.status_code == 204
    after = ok(client.get(TARGETS, headers=ana))
    assert (after["current"], after["history"]) == (None, [])
