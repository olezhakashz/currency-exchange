"""Lab 07: registration, login, caller identification and authorisation.

Every rejected case calls the service directly (no app, no hidden buttons),
so it shows the service itself refuses the request.
Run from backend/:  python -m pytest -v tests/test_lab07.py
"""
import json
import sqlite3
import time
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import db
from app.auth import AuthService
from app.config import Settings
from app.main import create_app
from seed import SAMPLE, load_rates

SECRET = "test-secret-key-0123456789abcdef0123456789"
PUBLIC = {("GET", "/health"), ("GET", "/rates"), ("POST", "/auth/register"), ("POST", "/auth/login")}


@pytest.fixture()
def env(tmp_path: Path):
    settings = Settings(database_path=tmp_path / "test.db", secret_key=SECRET,
                        token_ttl_seconds=3600, start_balance_pln="1000.00")
    app = create_app(settings)
    conn = db.connect(settings.database_path)
    load_rates(conn, json.loads(SAMPLE.read_text())[0])
    auth = AuthService(conn, SECRET, 3600, "1000.00")
    auth.register("admin@example.com", "admin-pass-1", role="ADMIN")
    conn.close()
    return TestClient(app), app, settings


def register(client, email, password="secret-pass-1"):
    r = client.post("/auth/register", json={"email": email, "password": password})
    assert r.status_code == 201, r.text
    return r.json()["userId"], {"Authorization": f"Bearer {r.json()['token']}"}


def login(client, email, password):
    r = client.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def admin(client):
    return login(client, "admin@example.com", "admin-pass-1")


def order(**kw):
    return {"requestId": str(uuid.uuid4()), "side": "BUY", "currency": "EUR",
            "amount": 10, "seenRate": 4.2650, **kw}


def code(r):
    return r.json()["error"]["code"]


# ---- registration and login (valid paths) -------------------------------
def test_register_then_login_returns_identity(env):
    client, _, _ = env
    uid, _ = register(client, "ola@example.com")
    r = client.post("/auth/login", json={"email": "Ola@Example.com ", "password": "secret-pass-1"})
    assert r.status_code == 200
    assert r.json()["user"] == {"id": uid, "email": "ola@example.com", "role": "USER"}
    me = client.get("/me", headers={"Authorization": f"Bearer {r.json()['token']}"})
    assert me.status_code == 200
    assert me.json()["id"] == uid and me.json()["role"] == "USER" and me.json()["disabled"] is False


def test_registration_cannot_choose_admin_role(env):
    client, _, _ = env
    r = client.post("/auth/register", json={"email": "x@example.com", "password": "secret-pass-1", "role": "ADMIN"})
    assert r.status_code == 400 and code(r) == "VALIDATION_ERROR"
    assert r.json()["error"]["details"][0]["field"] == "role"


# ---- identification: who is calling ---------------------------------------
def test_every_protected_route_refuses_anonymous_caller(env):
    """Walks all routes of the app, so a new endpoint can't forget the check."""
    client, app, _ = env
    checked = 0
    for route in app.routes:
        for method in getattr(route, "methods", ()) or ():
            if method in ("HEAD", "OPTIONS") or not route.path.startswith("/") or route.path.startswith(("/docs", "/openapi", "/redoc")):
                continue
            if (method, route.path) in PUBLIC:
                continue
            path = (route.path.replace("{user_id}", "1").replace("{request_id}", str(uuid.uuid4()))
                    .replace("{code}", "EUR"))
            r = client.request(method, path, json={})
            assert r.status_code == 401 and code(r) == "UNAUTHORIZED", (method, path, r.status_code)
            checked += 1
    assert checked >= 12


def test_forged_or_edited_token_is_refused(env):
    client, _, _ = env
    uid, h = register(client, "ola@example.com")
    other_id, _ = register(client, "eve@example.com")
    token = h["Authorization"].split()[1]
    _, ver, exp, sig = token.split(".")
    edited = f"{other_id}.{ver}.{exp}.{sig}"          # change the user id, keep the signature
    r = client.get("/wallet", headers={"Authorization": f"Bearer {edited}"})
    assert r.status_code == 401 and code(r) == "UNAUTHORIZED"
    later = f"{uid}.{ver}.{int(exp) + 10**6}.{sig}"   # extend the expiry
    assert client.get("/wallet", headers={"Authorization": f"Bearer {later}"}).status_code == 401


def test_expired_token(env, monkeypatch):
    client, _, _ = env
    _, h = register(client, "ola@example.com")
    monkeypatch.setattr(time, "time", lambda: 10**10)
    r = client.get("/me", headers=h)
    assert r.status_code == 401 and code(r) == "TOKEN_EXPIRED"


def test_logout_revokes_tokens(env):
    client, _, _ = env
    _, h = register(client, "ola@example.com")
    assert client.post("/auth/logout", headers=h).json() == {"status": "LOGGED_OUT"}
    r = client.get("/wallet", headers=h)
    assert r.status_code == 401 and code(r) == "TOKEN_REVOKED"
    r = client.post("/orders", json=order(), headers=h)
    assert r.status_code == 401 and code(r) == "TOKEN_REVOKED"
    h2 = login(client, "ola@example.com", "secret-pass-1")   # a new login works again
    assert client.get("/wallet", headers=h2).status_code == 200


# ---- accounts and wallets: own data only ---------------------------------
def test_user_sees_own_account_and_wallet_by_id(env):
    client, _, _ = env
    uid, h = register(client, "ola@example.com")
    assert client.get(f"/users/{uid}", headers=h).json()["email"] == "ola@example.com"
    assert client.get(f"/users/{uid}/wallet", headers=h).json() == {"userId": uid, "balances": {"PLN": 1000.0}}


@pytest.mark.parametrize("path", ["/users/{id}", "/users/{id}/wallet", "/users/{id}/orders"])
def test_user_cannot_read_another_users_records(env, path):
    client, _, _ = env
    _, h_ola = register(client, "ola@example.com")
    eve_id, _ = register(client, "eve@example.com")
    r = client.get(path.format(id=eve_id), headers=h_ola)
    assert r.status_code == 403 and code(r) == "FORBIDDEN"
    # An id that doesn't exist gives the same answer, so ids can't be probed.
    r = client.get(path.format(id=9999), headers=h_ola)
    assert r.status_code == 403 and code(r) == "FORBIDDEN"


def test_order_body_cannot_name_another_wallet(env, tmp_path):
    client, _, settings = env
    ola_id, h_ola = register(client, "ola@example.com")
    eve_id, _ = register(client, "eve@example.com")
    r = client.post("/orders", json={**order(), "userId": eve_id}, headers=h_ola)
    assert r.status_code == 400 and code(r) == "VALIDATION_ERROR"
    r = client.post("/orders", json=order(), headers=h_ola)
    assert r.status_code == 200
    rows = sqlite3.connect(settings.database_path).execute("SELECT user_id FROM orders").fetchall()
    assert rows == [(ola_id,)]   # the order went to the caller's wallet only


# ---- orders ("reservations" in the lab text) -------------------------------
def test_orders_are_listed_and_visible_only_to_their_owner(env):
    client, _, _ = env
    _, h_ola = register(client, "ola@example.com")
    _, h_eve = register(client, "eve@example.com")
    body = order()
    client.post("/orders", json=body, headers=h_ola)
    mine = client.get("/orders", headers=h_ola).json()["orders"]
    assert [o["requestId"] for o in mine] == [body["requestId"]]
    assert client.get("/orders", headers=h_eve).json() == {"orders": []}
    r = client.get(f"/orders/{body['requestId']}", headers=h_eve)
    assert r.status_code == 404 and r.json()["status"] == "NOT_FOUND"
    # Eve re-sending Ola's requestId can't replay Ola's answer or touch her wallet.
    r = client.post("/orders", json=body, headers=h_eve)
    assert r.status_code == 409 and code(r) == "REQUEST_ID_REUSED"
    assert "balances" not in r.json()


# ---- administration ---------------------------------------------------------
ADMIN_CALLS = [("GET", "/admin/users", None), ("POST", "/admin/users/{id}/disable", None),
               ("POST", "/admin/users/{id}/enable", None), ("PUT", "/admin/rates/EUR", {"mid": 1.0}),
               ("GET", "/admin/actions", None)]


@pytest.mark.parametrize("method, path, body", ADMIN_CALLS)
def test_normal_user_cannot_use_admin_functions(env, method, path, body):
    client, _, settings = env
    uid, h = register(client, "ola@example.com")
    r = client.request(method, path.format(id=uid), json=body, headers=h)
    assert r.status_code == 403 and code(r) == "FORBIDDEN"
    conn = sqlite3.connect(settings.database_path)
    assert conn.execute("SELECT COUNT(*) FROM admin_actions").fetchone()[0] == 0
    assert conn.execute("SELECT mid_e4 FROM rates WHERE currency='EUR'").fetchone()[0] == 42650


def test_admin_can_read_any_account_and_wallet(env):
    client, _, _ = env
    ola_id, h_ola = register(client, "ola@example.com")
    client.post("/orders", json=order(), headers=h_ola)
    h = admin(client)
    users = client.get("/admin/users", headers=h).json()["users"]
    assert [(u["email"], u["role"]) for u in users] == [("admin@example.com", "ADMIN"), ("ola@example.com", "USER")]
    assert client.get(f"/users/{ola_id}/wallet", headers=h).json()["balances"] == {"PLN": 957.35, "EUR": 10.0}
    assert len(client.get(f"/users/{ola_id}/orders", headers=h).json()["orders"]) == 1
    r = client.get("/users/9999", headers=h)
    assert r.status_code == 404 and code(r) == "USER_NOT_FOUND"


def test_admin_disables_account_and_its_token_stops_at_once(env):
    client, _, _ = env
    ola_id, h_ola = register(client, "ola@example.com")
    h = admin(client)
    r = client.post(f"/admin/users/{ola_id}/disable", headers=h)
    assert r.status_code == 200 and r.json()["disabled"] is True
    r = client.post("/orders", json=order(), headers=h_ola)           # token still unexpired
    assert r.status_code == 403 and code(r) == "ACCOUNT_DISABLED"
    r = client.post("/auth/login", json={"email": "ola@example.com", "password": "secret-pass-1"})
    assert r.status_code == 403 and code(r) == "ACCOUNT_DISABLED"
    r = client.post("/auth/login", json={"email": "ola@example.com", "password": "wrong-pass-1"})
    assert r.status_code == 401 and code(r) == "BAD_CREDENTIALS"     # wrong password says nothing more
    client.post(f"/admin/users/{ola_id}/enable", headers=h)
    assert client.get("/wallet", headers=h_ola).json()["error"]["code"] == "TOKEN_REVOKED"  # old token stays dead
    assert client.get("/wallet", headers=login(client, "ola@example.com", "secret-pass-1")).status_code == 200
    actions = [a["action"] for a in client.get("/admin/actions", headers=h).json()["actions"]]
    assert actions == ["ENABLE_USER", "DISABLE_USER"]


def test_admin_cannot_disable_self(env):
    client, _, _ = env
    h = admin(client)
    me = client.get("/me", headers=h).json()
    r = client.post(f"/admin/users/{me['id']}/disable", headers=h)
    assert r.status_code == 400 and code(r) == "CANNOT_DISABLE_SELF"


def test_admin_sets_rate_and_users_see_rate_changed(env):
    client, _, _ = env
    _, h_ola = register(client, "ola@example.com")
    h = admin(client)
    r = client.put("/admin/rates/EUR", json={"mid": 4.2710}, headers=h)
    assert r.status_code == 200 and r.json()["mid"] == 4.271
    assert client.put("/admin/rates/EUR", json={"mid": -1}, headers=h).status_code == 400
    assert code(client.put("/admin/rates/XYZ", json={"mid": 1}, headers=h)) == "UNKNOWN_CURRENCY"
    r = client.post("/orders", json=order(), headers=h_ola)        # still the old rate 4.2650
    assert r.status_code == 409 and r.json()["reason"] == "RATE_CHANGED"


def test_role_comes_from_database_not_token(env):
    """Demoting an admin in the database takes effect on the next request."""
    client, _, settings = env
    h = admin(client)
    assert client.get("/admin/users", headers=h).status_code == 200
    conn = sqlite3.connect(settings.database_path)
    conn.execute("UPDATE users SET role = 'USER' WHERE email = 'admin@example.com'")
    conn.commit()
    assert client.get("/admin/users", headers=h).status_code == 403


def test_old_lab06_database_gets_new_columns(tmp_path):
    path = tmp_path / "old.db"
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, "
                 "password_hash TEXT NOT NULL, created_at TEXT NOT NULL)")
    conn.commit()
    conn.close()
    create_app(Settings(database_path=path, secret_key=SECRET, token_ttl_seconds=60, start_balance_pln="1000.00"))
    cols = {r[1] for r in sqlite3.connect(path).execute("PRAGMA table_info(users)")}
    assert {"role", "disabled", "token_version"} <= cols
