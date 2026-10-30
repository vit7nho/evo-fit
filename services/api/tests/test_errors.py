from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, Field

from app.core.errors import PROBLEM_MEDIA_TYPE, AppError


class _Payload(BaseModel):
    reps: int = Field(ge=0, le=200)


def _add_probe_routes(app: FastAPI) -> None:
    router = APIRouter(prefix="/api/v1/_probe")

    @router.post("/validate")
    def validate(payload: _Payload) -> dict[str, int]:
        return {"reps": payload.reps}

    @router.get("/business")
    def business() -> None:
        raise AppError(409, "session_in_progress", "Conflito", "Já existe uma sessão em andamento.")

    @router.get("/boom")
    def boom() -> None:
        raise RuntimeError("detalhe interno que não pode vazar")

    app.include_router(router)


def _assert_problem(response, status: int, code: str) -> dict:
    assert response.status_code == status
    assert response.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body = response.json()
    assert body["status"] == status
    assert body["code"] == code
    assert body["type"].endswith(code.replace("_", "-"))
    assert body["request_id"] == response.headers["x-request-id"]
    return body


def test_unknown_route_returns_problem_404_in_portuguese(client_without_db: TestClient) -> None:
    body = _assert_problem(client_without_db.get("/api/v1/nao-existe"), 404, "not_found")
    assert body["title"] == "Não encontrado"
    assert body["detail"] is None


def test_wrong_method_returns_problem_405(client_without_db: TestClient) -> None:
    body = _assert_problem(client_without_db.delete("/api/v1/health"), 405, "method_not_allowed")
    assert body["title"] == "Método não permitido"


def test_validation_error_lists_fields_without_location_prefix(
    app: FastAPI, client_without_db: TestClient
) -> None:
    _add_probe_routes(app)
    body = _assert_problem(
        client_without_db.post("/api/v1/_probe/validate", json={"reps": 999}),
        422,
        "validation_error",
    )
    assert [e["field"] for e in body["errors"]] == ["reps"]


def test_business_error_keeps_code_and_detail(app: FastAPI, client_without_db: TestClient) -> None:
    _add_probe_routes(app)
    body = _assert_problem(
        client_without_db.get("/api/v1/_probe/business"), 409, "session_in_progress"
    )
    assert body["detail"] == "Já existe uma sessão em andamento."


def test_unhandled_error_does_not_leak_internals(
    app: FastAPI, client_without_db: TestClient
) -> None:
    _add_probe_routes(app)
    response = client_without_db.get("/api/v1/_probe/boom")
    body = _assert_problem(response, 500, "internal_error")
    assert "detalhe interno" not in response.text
    assert "Traceback" not in response.text
    assert body["request_id"]


def test_safe_request_id_from_client_is_echoed(client_without_db: TestClient) -> None:
    response = client_without_db.get("/api/v1/nao-existe", headers={"X-Request-ID": "abc-123"})
    assert response.headers["x-request-id"] == "abc-123"


def test_unsafe_request_id_is_replaced(client_without_db: TestClient) -> None:
    response = client_without_db.get(
        "/api/v1/nao-existe", headers={"X-Request-ID": "x\nfake-log-line"}
    )
    assert response.headers["x-request-id"] != "x\nfake-log-line"
    assert len(response.headers["x-request-id"]) == 32
