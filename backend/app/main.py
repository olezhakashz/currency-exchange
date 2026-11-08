"""HTTP layer (controllers). Only parsing and wiring here; rules live in the services.

Run:  uvicorn app.main:create_app --factory --port 8000      (from the backend/ folder)
Docs: http://127.0.0.1:8000/docs
"""
import os
import subprocess
from decimal import Decimal
from typing import Iterator, Literal
from uuid import UUID

from fastapi import Depends, FastAPI, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from . import db
from .auth import AuthService
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
    app = FastAPI(title="Currency Exchange API", version="0.5.0")
    install_handlers(app)

    def get_conn() -> Iterator:
        conn = db.connect(settings.database_path)
        try:
            yield conn
        finally:
            conn.close()

    def auth_service(conn=Depends(get_conn)) -> AuthService:
        return AuthService(conn, settings.secret_key, settings.token_ttl_seconds, settings.start_balance_pln)

    def current_user(authorization: str | None = Header(default=None),
                     auth: AuthService = Depends(auth_service)) -> int:
        return auth.check_token(authorization)

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
        return {"token": auth.login(body.email, body.password)}

    @app.get("/rates")
    def rates(conn=Depends(get_conn)):
        return RateService(conn).current_rates()

    @app.get("/wallet")
    def wallet(user_id: int = Depends(current_user), conn=Depends(get_conn)):
        return {"balances": WalletRepository(conn).balances(user_id)}

    @app.post("/orders")
    def place_order(body: OrderRequest, user_id: int = Depends(current_user), conn=Depends(get_conn)):
        status, result, replayed = OrderService(conn).execute(
            user_id, str(body.requestId), body.side, body.currency, body.amount, body.seenRate
        )
        return JSONResponse(result, status_code=status,
                            headers={"Idempotent-Replayed": "true" if replayed else "false"})

    @app.get("/orders/{request_id}")
    def order_status(request_id: UUID, user_id: int = Depends(current_user), conn=Depends(get_conn)):
        status, result = OrderService(conn).status(user_id, str(request_id))
        return JSONResponse(result, status_code=status)

    return app

