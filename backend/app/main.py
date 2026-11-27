"""HTTP layer (controllers). Only parsing and wiring here; rules live in the services.

Lab 07: every endpoint that touches a user's data first identifies the caller
(`current_user`, from the token) and then applies one rule from authz.py.
The user id is always taken from the token, never from the request body.

Run:  uvicorn app.main:create_app --factory --port 8000      (from the backend/ folder)
Docs: http://127.0.0.1:8000/docs
"""
import logging
import os
import subprocess
from decimal import Decimal
from typing import Iterator, Literal
from uuid import UUID

from fastapi import Depends, FastAPI, Header, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from . import db
from .accounts import AccountService, AdminService
from .auth import AuthService, Caller
from .authz import require_admin, require_self_or_admin
from .config import Settings, get_settings
from .errors import install_handlers
from .services import OrderService, RateService, WalletRepository


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)


class OrderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    requestId: UUID
    side: Literal["BUY", "SELL"]
    currency: str = Field(min_length=1, max_length=10)
    amount: Decimal
    seenRate: Decimal


class RateUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mid: Decimal


def git_revision() -> str:
    """Commit the server runs from, shown by /health so a demo can be tied to a revision."""
    try:
        out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                             timeout=2, cwd=os.path.dirname(__file__))
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], capture_output=True,
                               text=True, timeout=2, cwd=os.path.dirname(__file__))
        if out.returncode == 0:
            return out.stdout.strip() + ("-dirty" if dirty.stdout.strip() else "")
    except (OSError, subprocess.SubprocessError):
        pass
    return os.environ.get("APP_REVISION", "unknown")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()  # fails fast if SECRET_KEY is not set
    conn = db.connect(settings.database_path)
    db.init_schema(conn)
    conn.close()

    revision = git_revision()
    app = FastAPI(title="Currency Exchange API", version="0.7.0")
    install_handlers(app)

    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                           allow_methods=["GET", "POST", "PUT"], allow_headers=["Authorization", "Content-Type", "X-Client"],
                           expose_headers=["Idempotent-Replayed"])

    log = logging.getLogger("uvicorn.error")

    @app.middleware("http")
    async def log_client(request: Request, call_next):
        # One line per request, naming the client, so a demo can show that the
        # phone's request (not curl) reached the service.
        response = await call_next(request)
        # Lab 07: also the identified caller ("user 2 USER"), or "anonymous"
        # when no valid token was given, so refused requests are visible.
        if request.method != "OPTIONS":
            caller = getattr(request.state, "caller", None)
            who = f"user {caller.id} {caller.role}" if caller else "anonymous"
            log.info("request %s %s from %s as %s -> %s", request.method, request.url.path,
                     request.headers.get("x-client", request.headers.get("user-agent", "?")), who,
                     response.status_code)
        return response

    def get_conn() -> Iterator:
        conn = db.connect(settings.database_path)
        try:
            yield conn
        finally:
            conn.close()

    def auth_service(conn=Depends(get_conn)) -> AuthService:
        return AuthService(conn, settings.secret_key, settings.token_ttl_seconds, settings.start_balance_pln)

    def current_user(request: Request, authorization: str | None = Header(default=None),
                     auth: AuthService = Depends(auth_service)) -> Caller:
        caller = auth.identify(authorization)
        request.state.caller = caller
        return caller

    def admin_user(caller: Caller = Depends(current_user)) -> Caller:
        require_admin(caller)
        return caller

    @app.get("/health")
    def health(conn=Depends(get_conn)):
        conn.execute("SELECT 1")
        return {"status": "ok", "database": "ok", "revision": revision}

    @app.post("/auth/register", status_code=201)
    def register(body: Credentials, auth: AuthService = Depends(auth_service)):
        user_id = auth.register(body.email, body.password)
        return {"userId": user_id, "token": auth.make_token(user_id)}

    @app.post("/auth/login")
    def login(body: Credentials, auth: AuthService = Depends(auth_service)):
        token, caller = auth.login(body.email, body.password)
        return {"token": token, "user": {"id": caller.id, "email": caller.email, "role": caller.role}}

    @app.post("/auth/logout")
    def logout(caller: Caller = Depends(current_user), auth: AuthService = Depends(auth_service)):
        auth.logout(caller)
        return {"status": "LOGGED_OUT"}

    # ---- own account (the id comes from the token) ----------------------
    @app.get("/me")
    def me(caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        return AccountService(conn).get(caller.id)

    @app.get("/rates")
    def rates(conn=Depends(get_conn)):
        return RateService(conn).current_rates()

    @app.get("/wallet")
    def wallet(caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        return {"balances": WalletRepository(conn).balances(caller.id)}

    @app.get("/orders")
    def my_orders(caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        return {"orders": AccountService(conn).orders(caller.id)}

    @app.post("/orders")
    def place_order(body: OrderRequest, caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        # Always the caller's own wallet: the body has no userId (extra="forbid").
        status, result, replayed = OrderService(conn).execute(
            caller.id, str(body.requestId), body.side, body.currency, body.amount, body.seenRate
        )
        return JSONResponse(result, status_code=status,
                            headers={"Idempotent-Replayed": "true" if replayed else "false"})

    @app.get("/orders/{request_id}")
    def order_status(request_id: UUID, caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        status, result = OrderService(conn).status(caller.id, str(request_id))
        return JSONResponse(result, status_code=status)

    # ---- an account by id: that user or an admin -------------------------
    @app.get("/users/{user_id}")
    def user_account(user_id: int, caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        require_self_or_admin(caller, user_id)
        return AccountService(conn).get(user_id)

    @app.get("/users/{user_id}/wallet")
    def user_wallet(user_id: int, caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        require_self_or_admin(caller, user_id)
        return AccountService(conn).wallet(user_id)

    @app.get("/users/{user_id}/orders")
    def user_orders(user_id: int, caller: Caller = Depends(current_user), conn=Depends(get_conn)):
        require_self_or_admin(caller, user_id)
        AccountService(conn).get(user_id)
        return {"userId": user_id, "orders": AccountService(conn).orders(user_id)}

    # ---- administration: role ADMIN only ---------------------------------
    @app.get("/admin/users")
    def admin_users(admin: Caller = Depends(admin_user), conn=Depends(get_conn)):
        return {"users": AdminService(conn, admin).list_users()}

    @app.post("/admin/users/{user_id}/disable")
    def admin_disable(user_id: int, admin: Caller = Depends(admin_user), conn=Depends(get_conn)):
        return AdminService(conn, admin).set_disabled(user_id, True)

    @app.post("/admin/users/{user_id}/enable")
    def admin_enable(user_id: int, admin: Caller = Depends(admin_user), conn=Depends(get_conn)):
        return AdminService(conn, admin).set_disabled(user_id, False)

    @app.put("/admin/rates/{code}")
    def admin_set_rate(code: str, body: RateUpdate, admin: Caller = Depends(admin_user), conn=Depends(get_conn)):
        return AdminService(conn, admin).set_rate(code, body.mid)

    @app.get("/admin/actions")
    def admin_actions(limit: int = Query(default=50, ge=1, le=500), admin: Caller = Depends(admin_user),
                      conn=Depends(get_conn)):
        return {"actions": AdminService(conn, admin).actions(limit)}

    return app

