"""API tests against a real (temporary) SQLite database.

Run from backend/:  python -m pytest -v
"""
import json
import sqlite3
import threading
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import db
from app.config import Settings
from app.main import create_app
from seed import SAMPLE, load_rates

SECRET = "test-secret-key-0123456789abcdef0123456789"


@pytest.fixture()
def env(tmp_path: Path):
    settings = Settings(database_path=tmp_path / "test.db", secret_key=SECRET,
                        token_ttl_seconds=3600, start_balance_pln="1000.00")
    app = create_app(settings)
    conn = db.connect(settings.database_path)
    load_rates(conn, json.loads(SAMPLE.read_text())[0])
    conn.close()
    client = TestClient(app)
    return client, settings.database_path


def register(client, email="ola@example.com", password="secret-pass-1"):
    r = client.post("/auth/register", json={"email": email, "password": password})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def order(side="BUY", currency="EUR", amount=100.00, seen=4.2650, rid=None):
    return {"requestId": rid or str(uuid.uuid4()), "side": side, "currency": currency,
            "amount": amount, "seenRate": seen}


def db_rows(path, sql, args=()):
    conn = sqlite3.connect(path)
    rows = conn.execute(sql, args).fetchall()
    conn.close()
    return rows


# ---- read path -----------------------------------------------------------
def test_rates_are_read_from_database(env):
    client, _ = env
    r = client.get("/rates")
    assert r.status_code == 200
    body = r.json()
    assert body["effectiveDate"] == "2026-11-06"
    assert {"code": "EUR", "mid": 4.265} in body["rates"]
    assert isinstance(body["stale"], bool)


def test_new_wallet_has_1000_pln(env):
    client, _ = env
    h = register(client)
    r = client.get("/wallet", headers=h)
    assert r.status_code == 200
    assert r.json() == {"balances": {"PLN": 1000.0}}


def test_wallet_needs_token(env):
    client, _ = env
    r = client.get("/wallet")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHORIZED"
    r = client.get("/wallet", headers={"Authorization": "Bearer 1.9999999999.forged"})
    assert r.status_code == 401


# ---- write path ----------------------------------------------------------
def test_buy_commits_order_and_balances(env):
    client, path = env
    h = register(client)
    body = order()
    r = client.post("/orders", json=body, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "CONFIRMED"
    assert r.json()["balances"] == {"PLN": 573.5, "EUR": 100.0}
    assert r.headers["Idempotent-Replayed"] == "false"

    # Stored in the database, visible through the read endpoints.
    assert client.get("/wallet", headers=h).json()["balances"] == {"PLN": 573.5, "EUR": 100.0}
    s = client.get(f"/orders/{body['requestId']}", headers=h)
    assert s.status_code == 200 and s.json()["status"] == "CONFIRMED"
    assert db_rows(path, "SELECT status, amount_minor, pln_minor FROM orders") == [("CONFIRMED", 10000, 42650)]


def test_sell_after_buy(env):
    client, _ = env
    h = register(client)
    client.post("/orders", json=order(amount=100), headers=h)
    r = client.post("/orders", json=order(side="SELL", amount=40), headers=h)
    assert r.status_code == 200
    assert r.json()["balances"] == {"PLN": 744.1, "EUR": 60.0}


def test_same_request_id_runs_once(env):
    client, path = env
    h = register(client)
    body = order()
    first = client.post("/orders", json=body, headers=h)
    again = client.post("/orders", json=body, headers=h)
    assert again.status_code == 200
    assert again.json() == first.json()
    assert again.headers["Idempotent-Replayed"] == "true"
    assert db_rows(path, "SELECT COUNT(*) FROM orders")[0][0] == 1
    assert client.get("/wallet", headers=h).json()["balances"]["PLN"] == 573.5


def test_request_id_reused_for_other_order(env):
    client, _ = env
    h = register(client)
    body = order()
    client.post("/orders", json=body, headers=h)
    r = client.post("/orders", json={**body, "amount": 5}, headers=h)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "REQUEST_ID_REUSED"


def test_rate_changed_is_rejected_and_saved(env):
    client, path = env
    h = register(client)
    body = order(seen=4.2600)
    r = client.post("/orders", json=body, headers=h)
    assert r.status_code == 409
    assert r.json() == {"requestId": body["requestId"], "status": "REJECTED",
                        "reason": "RATE_CHANGED", "currentRate": 4.265}
    assert client.get("/wallet", headers=h).json()["balances"] == {"PLN": 1000.0}
    assert client.get(f"/orders/{body['requestId']}", headers=h).json()["reason"] == "RATE_CHANGED"


def test_insufficient_funds(env):
    client, _ = env
    h = register(client)
    r = client.post("/orders", json=order(amount=500), headers=h)  # needs 2132.50 PLN
    assert r.status_code == 409
    assert r.json()["reason"] == "INSUFFICIENT_FUNDS"
    assert r.json()["needed"] == {"PLN": 2132.5}
    r = client.post("/orders", json=order(side="SELL", amount=1), headers=h)  # has no EUR
    assert r.json()["reason"] == "INSUFFICIENT_FUNDS"
    assert client.get("/wallet", headers=h).json()["balances"] == {"PLN": 1000.0}


def test_two_parallel_orders_cannot_overspend(env):
    client, _ = env
    h = register(client)
    results = []

    def buy():  # each needs 852.93 PLN; only one fits in 1000 PLN
        results.append(client.post("/orders", json=order(currency="USD", amount=218.03, seen=3.9120), headers=h))

    threads = [threading.Thread(target=buy) for _ in range(4)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    statuses = sorted(r.json()["status"] for r in results)
    assert statuses == ["CONFIRMED", "REJECTED", "REJECTED", "REJECTED"]
    assert client.get("/wallet", headers=h).json()["balances"]["PLN"] == pytest.approx(147.07)


# ---- validation at the boundary -----------------------------------------
@pytest.mark.parametrize("change, code, field", [
    ({"amount": 0}, "INVALID_AMOUNT", "amount"),
    ({"amount": -5}, "INVALID_AMOUNT", "amount"),
    ({"amount": 10.555}, "INVALID_AMOUNT", "amount"),
    ({"amount": 5_000_000}, "INVALID_AMOUNT", "amount"),
    ({"currency": "XYZ"}, "UNKNOWN_CURRENCY", "currency"),
    ({"currency": "PLN"}, "UNKNOWN_CURRENCY", "currency"),
    ({"currency": "E1"}, "UNKNOWN_CURRENCY", "currency"),
    ({"seenRate": 0}, "INVALID_RATE", "seenRate"),
    ({"side": "HOLD"}, "VALIDATION_ERROR", "side"),
    ({"requestId": "abc"}, "VALIDATION_ERROR", "requestId"),
    ({"amount": "lots"}, "VALIDATION_ERROR", "amount"),
    ({"extra": 1}, "VALIDATION_ERROR", "extra"),
])
def test_bad_order_input(env, change, code, field):
    client, path = env
    h = register(client)
    r = client.post("/orders", json={**order(), **change}, headers=h)
    assert r.status_code == 400, r.text
    err = r.json()["error"]
    assert err["code"] == code
    assert err["details"][0]["field"] == field
    assert db_rows(path, "SELECT COUNT(*) FROM orders")[0][0] == 0


def test_missing_fields_are_listed(env):
    client, _ = env
    h = register(client)
    r = client.post("/orders", json={"side": "BUY"}, headers=h)
    assert r.status_code == 400
    fields = {d["field"] for d in r.json()["error"]["details"]}
    assert fields == {"requestId", "currency", "amount", "seenRate"}


def test_malformed_json(env):
    client, _ = env
    h = register(client)
    r = client.post("/orders", content=b"{not json", headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "MALFORMED_JSON"


def test_register_validation_and_duplicates(env):
    client, _ = env
    r = client.post("/auth/register", json={"email": "nope", "password": "short"})
    assert r.status_code == 400
    assert {d["field"] for d in r.json()["error"]["details"]} == {"email", "password"}
    register(client)
    r = client.post("/auth/register", json={"email": "OLA@example.com", "password": "secret-pass-1"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "EMAIL_TAKEN"


def test_login(env):
    client, _ = env
    register(client)
    assert client.post("/auth/login", json={"email": "ola@example.com", "password": "secret-pass-1"}).status_code == 200
    r = client.post("/auth/login", json={"email": "ola@example.com", "password": "wrong-pass"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "BAD_CREDENTIALS"


def test_order_status_not_found_and_other_users(env):
    client, _ = env
    h1 = register(client, "a@example.com")
    h2 = register(client, "b@example.com")
    body = order()
    client.post("/orders", json=body, headers=h1)
    r = client.get(f"/orders/{body['requestId']}", headers=h2)
    assert r.status_code == 404 and r.json()["status"] == "NOT_FOUND"
    r = client.get(f"/orders/{uuid.uuid4()}", headers=h1)
    assert r.status_code == 404 and r.json()["status"] == "NOT_FOUND"


def test_no_rates_gives_503(tmp_path):
    settings = Settings(database_path=tmp_path / "empty.db", secret_key=SECRET,
                        token_ttl_seconds=60, start_balance_pln="1000.00")
    r = TestClient(create_app(settings)).get("/rates")
    assert r.status_code == 503 and r.json()["error"]["code"] == "RATES_UNAVAILABLE"
