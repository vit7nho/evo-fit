from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from app import __version__
from app.db.session import get_db


def test_health_reports_ok_when_database_responds(client: TestClient) -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "database": "ok",
        "version": __version__,
        "environment": "test",
    }


class _BrokenSession:
    def execute(self, *_args, **_kwargs):
        raise OperationalError("SELECT 1", {}, Exception("conexão recusada"))


def test_health_reports_degraded_with_503_when_database_fails(app: FastAPI) -> None:
    app.dependency_overrides[get_db] = lambda: _BrokenSession()
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 503
    assert response.json()["status"] == "degraded"
    assert response.json()["database"] == "unavailable"
    assert "conexão recusada" not in response.text
