"""Lab 06: CORS for the Flutter web build (off unless CORS_ORIGINS is set)."""
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

SECRET = "x" * 40
ORIGIN = "http://127.0.0.1:8080"


def make(tmp_path, origins=()):
    return TestClient(create_app(Settings(database_path=tmp_path / "t.db", secret_key=SECRET,
                                          token_ttl_seconds=3600, start_balance_pln="1000.00",
                                          cors_origins=tuple(origins))))


def preflight(client, origin=ORIGIN):
    return client.options("/orders", headers={"Origin": origin, "Access-Control-Request-Method": "POST",
                                              "Access-Control-Request-Headers": "authorization,content-type,x-client"})


def test_cors_off_by_default(tmp_path):
    r = make(tmp_path).get("/health", headers={"Origin": ORIGIN})
    assert "access-control-allow-origin" not in r.headers


def test_cors_allows_configured_origin_and_exposes_replay_header(tmp_path):
    client = make(tmp_path, [ORIGIN])
    r = preflight(client)
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] == ORIGIN
    r = client.get("/health", headers={"Origin": ORIGIN})
    assert r.headers["access-control-allow-origin"] == ORIGIN
    assert "Idempotent-Replayed" in r.headers["access-control-expose-headers"]


def test_cors_refuses_other_origin(tmp_path):
    r = preflight(make(tmp_path, [ORIGIN]), origin="http://evil.example")
    assert r.status_code == 400
    assert "access-control-allow-origin" not in r.headers
