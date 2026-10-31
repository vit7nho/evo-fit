"""Perfil (PATCH /me), vocabulários e consentimentos."""

import logging

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.modules.users import vocabulary
from app.modules.users.models import ConsentKind, UserConsent

ONBOARDING = {
    "primary_objective": "gain_muscle",
    "secondary_objectives": ["general_health"],
    "preferred_modalities": ["strength", "walk"],
    "experience_level": "beginner",
    "weekly_availability": {"days_per_week": 3, "minutes_per_session": 45},
    "equipment": ["gym"],
    "onboarding_completed": True,
}


def me(client: TestClient, headers: dict[str, str]) -> dict:
    response = client.get("/api/v1/me", headers=headers)
    assert response.status_code == 200
    return response.json()


def patch(client: TestClient, headers: dict[str, str], body: dict):
    return client.patch("/api/v1/me", headers=headers, json=body)


def errors_of(response) -> list[str]:
    return [e["field"] for e in response.json()["errors"]]


# --- opções ---


def test_profile_options_are_public_ordered_and_cacheable(client: TestClient) -> None:
    response = client.get("/api/v1/profile-options")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=3600"
    body = response.json()
    assert [o["code"] for o in body["objectives"]] == list(vocabulary.OBJECTIVES)
    assert body["modalities"][0] == {"code": "strength", "label": "Musculação"}
    assert {o["code"] for o in body["limitation_tags"]} == set(vocabulary.LIMITATION_TAGS)


# --- onboarding e atualização ---


def test_new_account_starts_with_onboarding_pending(client: TestClient, signup) -> None:
    profile = me(client, signup())["profile"]
    assert profile["onboarding_completed_at"] is None
    assert profile["primary_objective"] is None
    assert profile["secondary_objectives"] == []
    assert profile["timezone"] == "America/Sao_Paulo"


def test_onboarding_saves_answers_and_completes_once(client: TestClient, signup) -> None:
    headers = signup()

    response = patch(client, headers, ONBOARDING)

    assert response.status_code == 200
    profile = response.json()["profile"]
    assert profile["primary_objective"] == "gain_muscle"
    assert profile["preferred_modalities"] == ["strength", "walk"]
    assert profile["weekly_availability"] == {"days_per_week": 3, "minutes_per_session": 45}
    completed_at = profile["onboarding_completed_at"]
    assert completed_at is not None

    again = patch(client, headers, {"onboarding_completed": True}).json()["profile"]
    assert again["onboarding_completed_at"] == completed_at  # não é reescrito


def test_patch_changes_only_the_fields_sent(client: TestClient, signup) -> None:
    headers = signup()
    patch(client, headers, ONBOARDING)

    profile = patch(client, headers, {"equipment": ["dumbbells", "bands"]}).json()["profile"]

    assert profile["equipment"] == ["dumbbells", "bands"]
    assert profile["preferred_modalities"] == ["strength", "walk"]
    assert profile["display_name"] == "Ana"


def test_null_clears_optional_fields_and_empties_lists(client: TestClient, signup) -> None:
    headers = signup()
    patch(client, headers, ONBOARDING)

    profile = patch(client, headers, {"experience_level": None, "equipment": None}).json()[
        "profile"
    ]

    assert profile["experience_level"] is None
    assert profile["equipment"] == []


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"display_name": None}, "display_name"),
        ({"timezone": None}, "timezone"),
        ({"timezone": "Lua/Base_Alfa"}, "timezone"),
        ({"primary_objective": "ficar_rico"}, "primary_objective"),
        ({"preferred_modalities": ["strength", "paraquedas"]}, "preferred_modalities"),
        ({"preferred_modalities": ["run", "run"]}, "preferred_modalities"),
        (
            {"weekly_availability": {"days_per_week": 8, "minutes_per_session": 30}},
            "weekly_availability.days_per_week",
        ),
        (
            {"weekly_availability": {"days_per_week": 3, "minutes_per_session": 5}},
            "weekly_availability.minutes_per_session",
        ),
        ({"birth_year": 1850}, "birth_year"),
        ({"birth_year": 2025}, "birth_year"),
        ({"experience_level": "lenda"}, "experience_level"),
        ({"onboarding_completed": False}, "onboarding_completed"),
        ({"email": "outro@exemplo.com"}, "email"),
        ({"user_id": "0192f0c0-0000-7000-8000-000000000001"}, "user_id"),
    ],
)
def test_invalid_profile_values_point_to_the_field(
    client: TestClient, signup, body: dict, field: str
) -> None:
    response = patch(client, signup(), body)
    assert response.status_code == 422
    assert errors_of(response) == [field]


def test_primary_objective_cannot_repeat_in_secondary(client: TestClient, signup) -> None:
    response = patch(
        client,
        signup(),
        {"primary_objective": "run", "secondary_objectives": ["run", "general_health"]},
    )
    assert response.status_code == 422
    assert errors_of(response) == ["secondary_objectives"]


def test_validation_messages_are_in_portuguese(client: TestClient, signup) -> None:
    response = patch(client, signup(), {"preferred_modalities": ["paraquedas"]})
    assert response.json()["errors"][0]["message"] == "Valor inválido: paraquedas."


def test_profile_requires_authentication(client: TestClient) -> None:
    response = patch(client, {}, {"display_name": "Invasor"})
    assert response.status_code == 401


def test_one_user_cannot_change_another_profile(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com", "Ana")
    bia = signup("bia@exemplo.com", "Bia")

    patch(client, bia, {"display_name": "Bia Atualizada", "equipment": ["pool"]})

    ana_profile = me(client, ana)["profile"]
    assert ana_profile["display_name"] == "Ana"
    assert ana_profile["equipment"] == []


# --- dados de saúde e consentimentos ---


def test_health_data_requires_consent(client: TestClient, signup) -> None:
    headers = signup()

    response = patch(
        client, headers, {"limitation_tags": ["knee"], "limitations_note": "Dor ao agachar"}
    )

    assert response.status_code == 403
    assert response.json()["code"] == "consent_required"
    profile = me(client, headers)["profile"]
    assert profile["limitation_tags"] == []
    assert profile["limitations_note"] is None


def test_clearing_health_data_never_needs_consent(client: TestClient, signup) -> None:
    response = patch(client, signup(), {"limitation_tags": [], "limitations_note": ""})
    assert response.status_code == 200


def test_health_data_is_saved_after_consent(client: TestClient, signup) -> None:
    headers = signup()

    grant = client.put("/api/v1/me/consents/health_data", headers=headers)
    assert grant.status_code == 200
    assert grant.json()["kind"] == "health_data"

    response = patch(
        client, headers, {"limitation_tags": ["knee"], "limitations_note": "Dor ao agachar"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["profile"]["limitation_tags"] == ["knee"]
    assert {c["kind"] for c in body["consents"]} == {"terms_privacy", "health_data"}


def test_granting_twice_keeps_a_single_active_consent(
    client: TestClient, signup, db: Session
) -> None:
    headers = signup()
    first = client.put("/api/v1/me/consents/ai_processing", headers=headers).json()
    second = client.put("/api/v1/me/consents/ai_processing", headers=headers).json()

    assert first["granted_at"] == second["granted_at"]
    count = db.scalar(
        select(func.count())
        .select_from(UserConsent)
        .where(UserConsent.kind == ConsentKind.AI_PROCESSING)
    )
    assert count == 1


def test_revoking_health_consent_erases_health_data(client: TestClient, signup) -> None:
    headers = signup()
    client.put("/api/v1/me/consents/health_data", headers=headers)
    patch(client, headers, {"limitation_tags": ["knee"], "limitations_note": "Dor ao agachar"})

    response = client.delete("/api/v1/me/consents/health_data", headers=headers)

    assert response.status_code == 204
    body = me(client, headers)
    assert body["profile"]["limitation_tags"] == []
    assert body["profile"]["limitations_note"] is None
    assert "health_data" not in {c["kind"] for c in body["consents"]}
    # Sem consentimento, novos dados de saúde voltam a ser recusados.
    assert patch(client, headers, {"limitation_tags": ["knee"]}).status_code == 403


def test_revoking_is_idempotent(client: TestClient, signup) -> None:
    headers = signup()
    assert client.delete("/api/v1/me/consents/ai_processing", headers=headers).status_code == 204
    assert client.delete("/api/v1/me/consents/ai_processing", headers=headers).status_code == 204


def test_terms_consent_is_managed_only_by_signup(client: TestClient, signup) -> None:
    headers = signup()

    grant = client.put("/api/v1/me/consents/terms_privacy", headers=headers)
    revoke = client.delete("/api/v1/me/consents/terms_privacy", headers=headers)

    assert grant.status_code == 422
    assert revoke.status_code == 409
    assert revoke.json()["code"] == "consent_not_revocable"


def test_unknown_consent_kind_is_rejected(client: TestClient, signup) -> None:
    response = client.put("/api/v1/me/consents/vender_dados", headers=signup())
    assert response.status_code == 422


def test_consent_of_one_user_does_not_unlock_another(client: TestClient, signup) -> None:
    ana = signup("ana@exemplo.com")
    bia = signup("bia@exemplo.com")
    client.put("/api/v1/me/consents/health_data", headers=ana)

    assert patch(client, bia, {"limitation_tags": ["knee"]}).status_code == 403


def test_health_note_never_reaches_the_logs(
    client: TestClient, signup, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    headers = signup()
    client.put("/api/v1/me/consents/health_data", headers=headers)

    patch(client, headers, {"limitations_note": "Hérnia de disco L5-S1"})

    text = caplog.text + "".join(str(vars(r)) for r in caplog.records)
    assert "Hérnia" not in text
    assert "limitations_note" in text  # o nome do campo alterado aparece; o valor, não
