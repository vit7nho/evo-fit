"""Nutrição (5.1): alimentos do catálogo e próprios, refeições com a cópia dos
nutrientes, totais do dia no fuso da pessoa, consentimento de saúde e escopo."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.nutrition.models import Food, MealItem
from tests.test_analytics import ok

API = "/api/v1"
ARROZ = {
    "name": "Arroz branco cozido",
    "kcal": 128,
    "protein_g": 2.5,
    "carbs_g": 28.1,
    "fat_g": 0.2,
    "fiber_g": 1.6,
    "default_portion_g": 150,
}
FRANGO = {
    "name": "Peito de frango grelhado",
    "kcal": 159,
    "protein_g": 32,
    "carbs_g": 0,
    "fat_g": 2.5,
}


@pytest.fixture
def ana(signup, client: TestClient) -> dict:
    headers = signup("ana@exemplo.com", "Ana")
    ok(client.put(f"{API}/me/consents/health_data", headers=headers))
    return headers


@pytest.fixture
def bia(signup) -> dict:
    return signup("bia@exemplo.com", "Bia")


def food(client: TestClient, headers: dict, body: dict) -> dict:
    return ok(client.post(f"{API}/foods", headers=headers, json=body), 201)


def meal(client: TestClient, headers: dict, items: list, **body) -> dict:
    payload = {
        "eaten_at": "2026-11-01T15:30:00Z",
        "meal_type": "lunch",
        "items": items,
        **body,
    }
    return ok(client.post(f"{API}/meals", headers=headers, json=payload), 201)


def test_options_are_public(client: TestClient) -> None:
    types = ok(client.get(f"{API}/nutrition-options"))["meal_types"]
    assert [t["code"] for t in types] == ["breakfast", "lunch", "dinner", "snack", "other"]
    assert types[0]["label"] == "Café da manhã"


# --- alimentos ---


def test_own_foods_search_and_privacy(
    client: TestClient, db: Session, ana: dict, bia: dict
) -> None:
    db.add(
        Food(
            name="Pão francês",
            search_name="pao frances",
            source="taco",
            source_ref="TACO 53",
            kcal=300,
            protein_g=8,
            carbs_g=58.6,
            fat_g=3.1,
            fiber_g=2.3,
            default_portion_g=50,
        )
    )
    db.commit()
    mine = food(client, ana, ARROZ)
    assert mine["mine"] is True and mine["source"] == "user"

    # Busca sem acento e por palavras; o catálogo é de todos, o próprio só da dona.
    found = ok(client.get(f"{API}/foods?q=PAO", headers=ana))
    assert [f["name"] for f in found] == ["Pão francês"]
    assert found[0]["mine"] is False and found[0]["source_ref"] == "TACO 53"
    assert [f["name"] for f in ok(client.get(f"{API}/foods?q=arroz cozido", headers=ana))] == [
        "Arroz branco cozido"
    ]
    assert [f["name"] for f in ok(client.get(f"{API}/foods?mine=true", headers=ana))] == [
        "Arroz branco cozido"
    ]
    assert [f["name"] for f in ok(client.get(f"{API}/foods", headers=bia))] == ["Pão francês"]
    assert client.get(f"{API}/foods/{mine['id']}", headers=bia).status_code == 404

    # Ninguém edita o catálogo; a Bia não edita nem apaga o da Ana.
    catalog_id = found[0]["id"]
    assert (
        client.patch(f"{API}/foods/{catalog_id}", headers=ana, json={"kcal": 1}).status_code == 404
    )
    assert (
        client.patch(f"{API}/foods/{mine['id']}", headers=bia, json={"kcal": 1}).status_code == 404
    )
    assert client.delete(f"{API}/foods/{mine['id']}", headers=bia).status_code == 404


@pytest.mark.parametrize(
    ("change", "field"),
    [
        ({"protein_g": 60, "carbs_g": 50}, "__root__"),
        ({"kcal": 901}, "kcal"),
        ({"fat_g": -1}, "fat_g"),
        ({"name": "A"}, "name"),
        ({"default_portion_g": 0}, "default_portion_g"),
    ],
)
def test_food_values_are_checked(client: TestClient, ana: dict, change: dict, field: str) -> None:
    response = client.post(f"{API}/foods", headers=ana, json={**ARROZ, **change})
    assert response.status_code == 422
    assert field in [e["field"] for e in response.json()["errors"]]


def test_food_update_keeps_the_rules(client: TestClient, ana: dict) -> None:
    mine = food(client, ana, ARROZ)
    updated = ok(client.patch(f"{API}/foods/{mine['id']}", headers=ana, json={"kcal": 130}))
    assert (updated["kcal"], updated["protein_g"]) == (130, 2.5)
    response = client.patch(f"{API}/foods/{mine['id']}", headers=ana, json={"carbs_g": 99})
    assert response.status_code == 422
    response = client.patch(f"{API}/foods/{mine['id']}", headers=ana, json={"name": None})
    assert response.status_code == 422


# --- refeições ---


def test_meals_need_the_health_consent(client: TestClient, bia: dict) -> None:
    arroz = food(client, bia, ARROZ)  # alimento próprio não é dado de saúde
    response = client.post(
        f"{API}/meals",
        headers=bia,
        json={
            "eaten_at": "2026-11-01T15:30:00Z",
            "meal_type": "lunch",
            "items": [{"food_id": arroz["id"], "quantity_g": 100}],
        },
    )
    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"


def test_meal_items_copy_the_nutrients_of_the_quantity(client: TestClient, ana: dict) -> None:
    arroz, frango = food(client, ana, ARROZ), food(client, ana, FRANGO)
    lunch = meal(
        client,
        ana,
        [
            {"food_id": arroz["id"], "quantity_g": 150},
            {"food_id": frango["id"], "quantity_g": 120},
        ],
        notes="Depois do treino",
    )
    rice, chicken = lunch["items"]
    assert (rice["food_name"], rice["quantity_g"]) == ("Arroz branco cozido", 150)
    assert (rice["kcal"], rice["protein_g"], rice["carbs_g"], rice["fiber_g"]) == (
        192.0,
        3.8,
        42.2,
        2.4,
    )
    # Frango sem fibra registrada: nulo, não zero.
    assert (chicken["kcal"], chicken["protein_g"], chicken["fiber_g"]) == (190.8, 38.4, None)
    assert lunch["totals"] == {
        "kcal": 382.8,
        "protein_g": 42.2,
        "carbs_g": 42.2,
        "fat_g": 3.3,
        "fiber_g": 2.4,
    }
    assert lunch["meal_type_label"] == "Almoço"
    assert lunch["notes"] == "Depois do treino"


def test_history_survives_editing_or_deleting_the_food(
    client: TestClient, db: Session, ana: dict
) -> None:
    arroz = food(client, ana, ARROZ)
    lunch = meal(client, ana, [{"food_id": arroz["id"], "quantity_g": 100}])
    ok(client.patch(f"{API}/foods/{arroz['id']}", headers=ana, json={"kcal": 999 // 10}))
    assert ok(client.get(f"{API}/meals/{lunch['id']}", headers=ana))["items"][0]["kcal"] == 128

    # Regravar a refeição recalcula pelos valores atuais.
    replaced = ok(
        client.put(
            f"{API}/meals/{lunch['id']}",
            headers=ana,
            json={
                "eaten_at": "2026-11-01T15:30:00Z",
                "meal_type": "dinner",
                "items": [{"food_id": arroz["id"], "quantity_g": 200}],
            },
        )
    )
    assert (replaced["meal_type"], replaced["items"][0]["kcal"]) == ("dinner", 198.0)

    assert client.delete(f"{API}/foods/{arroz['id']}", headers=ana).status_code == 204
    kept = ok(client.get(f"{API}/meals/{lunch['id']}", headers=ana))["items"][0]
    assert (kept["food_id"], kept["food_name"], kept["kcal"]) == (None, "Arroz branco cozido", 198)


def test_daily_totals_use_the_persons_time_zone(client: TestClient, ana: dict) -> None:
    arroz = food(client, ana, ARROZ)
    item = [{"food_id": arroz["id"], "quantity_g": 100}]
    meal(client, ana, item, eaten_at="2026-11-01T10:00:00Z", meal_type="breakfast")
    # 01h30 UTC do dia 2 ainda é 22h30 do dia 1 em São Paulo.
    meal(client, ana, item, eaten_at="2026-11-02T01:30:00Z", meal_type="dinner")
    meal(client, ana, item, eaten_at="2026-11-02T12:00:00Z")

    day = ok(client.get(f"{API}/nutrition/daily?date=2026-11-01", headers=ana))
    assert [m["meal_type"] for m in day["meals"]] == ["breakfast", "dinner"]
    assert day["totals"]["kcal"] == 256
    assert (
        ok(client.get(f"{API}/nutrition/daily?date=2026-11-02", headers=ana))["totals"]["kcal"]
        == 128
    )
    empty = ok(client.get(f"{API}/nutrition/daily?date=2026-10-01", headers=ana))
    assert empty["meals"] == []
    assert empty["totals"] == {
        "kcal": 0,
        "protein_g": 0,
        "carbs_g": 0,
        "fat_g": 0,
        "fiber_g": None,
    }


def test_meals_are_private_and_foods_must_be_visible(
    client: TestClient, ana: dict, bia: dict
) -> None:
    arroz = food(client, ana, ARROZ)
    lunch = meal(client, ana, [{"food_id": arroz["id"], "quantity_g": 100}])
    ok(client.put(f"{API}/me/consents/health_data", headers=bia))
    for method in ("GET", "DELETE"):
        response = client.request(method, f"{API}/meals/{lunch['id']}", headers=bia)
        assert response.status_code == 404
    assert ok(client.get(f"{API}/nutrition/daily?date=2026-11-01", headers=bia))["meals"] == []

    # A Bia não registra refeição com o alimento próprio da Ana.
    response = client.post(
        f"{API}/meals",
        headers=bia,
        json={
            "eaten_at": "2026-11-01T15:30:00Z",
            "meal_type": "lunch",
            "items": [{"food_id": arroz["id"], "quantity_g": 100}],
        },
    )
    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "items.0.food_id"


@pytest.mark.parametrize(
    "change",
    [
        {"items": []},
        {"items": [{"food_id": "00000000-0000-0000-0000-000000000000", "quantity_g": 0}]},
        {"meal_type": "ceia"},
        {"user_id": "00000000-0000-0000-0000-000000000000"},
    ],
)
def test_meal_input_is_checked(client: TestClient, ana: dict, change: dict) -> None:
    arroz = food(client, ana, ARROZ)
    body = {
        "eaten_at": "2026-11-01T15:30:00Z",
        "meal_type": "lunch",
        "items": [{"food_id": arroz["id"], "quantity_g": 100}],
        **change,
    }
    assert client.post(f"{API}/meals", headers=ana, json=body).status_code == 422


def test_revoking_health_data_deletes_the_meals(client: TestClient, db: Session, ana: dict) -> None:
    arroz = food(client, ana, ARROZ)
    lunch = meal(client, ana, [{"food_id": arroz["id"], "quantity_g": 100}])
    assert client.delete(f"{API}/me/consents/health_data", headers=ana).status_code == 204
    assert client.get(f"{API}/meals/{lunch['id']}", headers=ana).status_code == 404
    assert db.scalars(select(MealItem)).all() == []
    # Os alimentos próprios ficam (não são dado de saúde).
    assert ok(client.get(f"{API}/foods/{arroz['id']}", headers=ana))["name"] == ARROZ["name"]


def test_deleting_a_meal(client: TestClient, ana: dict) -> None:
    arroz = food(client, ana, ARROZ)
    lunch = meal(client, ana, [{"food_id": arroz["id"], "quantity_g": 100}])
    assert client.delete(f"{API}/meals/{lunch['id']}", headers=ana).status_code == 204
    assert client.get(f"{API}/meals/{lunch['id']}", headers=ana).status_code == 404


def test_a_time_without_zone_is_in_the_profiles_zone(client: TestClient, ana: dict) -> None:
    """O app manda o horário sem fuso: vale o do perfil, o mesmo que separa os dias
    (com o aparelho em outro fuso, a refeição não cai no dia anterior)."""
    arroz = food(client, ana, ARROZ)
    late = meal(
        client,
        ana,
        [{"food_id": arroz["id"], "quantity_g": 100}],
        eaten_at="2026-11-01T23:30:00",
        meal_type="dinner",
    )
    assert late["eaten_at"].startswith("2026-11-02T02:30:00")
    assert late["local_time"] == "2026-11-01T23:30:00"
    day = ok(client.get(f"{API}/nutrition/daily?date=2026-11-01", headers=ana))
    assert [m["local_time"] for m in day["meals"]] == ["2026-11-01T23:30:00"]
