import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import app

client = TestClient(app)


def preflight(origin: str):
    return client.options(
        "/api/v1/health",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
        },
    )


@pytest.mark.parametrize(
    "origin",
    ["http://localhost:61163", "http://127.0.0.1:52741"],
)
def test_development_dynamic_local_origin_is_allowed(origin: str) -> None:
    response = preflight(origin)

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert response.headers["access-control-allow-credentials"] == "true"


def test_unrelated_origin_is_rejected() -> None:
    response = preflight("https://example.com")

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_production_has_no_development_origin_regex() -> None:
    settings = Settings(app_env="production")

    assert settings.cors_origin_regex is None
    assert settings.cors_origins == [
        "http://localhost:3000",
        "http://localhost:8080",
    ]
