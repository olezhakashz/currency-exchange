"""AccountService and AdminService (Lab 07).

They don't check permissions themselves: the endpoint has already called a
rule from authz.py. They only read and change the data.
"""
import json
import sqlite3
from datetime import datetime, timezone
from decimal import Decimal

from .auth import Caller
from .errors import ApiError
from .money import decimals, rate_from_e4, rate_to_e4
from .services import CODE_RE, BASE, WalletRepository


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _account(row: sqlite3.Row) -> dict:
    return {"id": row["id"], "email": row["email"], "role": row["role"],
            "disabled": bool(row["disabled"]), "createdAt": row["created_at"]}


class AccountService:
    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def get(self, user_id: int) -> dict:
        row = self.conn.execute(
            "SELECT id, email, role, disabled, created_at FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        if row is None:
            raise ApiError(404, "USER_NOT_FOUND", f"No user with id {user_id}.")
        return _account(row)

    def wallet(self, user_id: int) -> dict:
        self.get(user_id)  # 404 for an unknown id
        return {"userId": user_id, "balances": WalletRepository(self.conn).balances(user_id)}

    def orders(self, user_id: int, limit: int = 50) -> list[dict]:
        rows = self.conn.execute(
            "SELECT response_json, created_at FROM orders WHERE user_id = ? "
            "ORDER BY created_at DESC, rowid DESC LIMIT ?",
            (user_id, limit),
        ).fetchall()
        out = []
        for r in rows:
            body = json.loads(r["response_json"])
            body.pop("balances", None)  # balances at that time; the wallet endpoint has today's
            body["createdAt"] = r["created_at"]
            out.append(body)
        return out


class AdminService:
    def __init__(self, conn: sqlite3.Connection, admin: Caller):
        self.conn = conn
        self.admin = admin
        self.accounts = AccountService(conn)

    def _log(self, action: str, target: str, detail: str | None = None) -> None:
        self.conn.execute(
            "INSERT INTO admin_actions (admin_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?)",
            (self.admin.id, action, target, detail, _now_iso()),
        )

    def list_users(self) -> list[dict]:
        rows = self.conn.execute(
            "SELECT id, email, role, disabled, created_at FROM users ORDER BY id").fetchall()
        return [_account(r) for r in rows]

    def set_disabled(self, user_id: int, disabled: bool) -> dict:
        if user_id == self.admin.id and disabled:
            raise ApiError(400, "CANNOT_DISABLE_SELF", "An administrator cannot disable their own account.")
        self.accounts.get(user_id)  # 404 for an unknown id
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            # token_version + 1 as well, so tokens issued before stay invalid
            # even after the account is enabled again.
            self.conn.execute(
                "UPDATE users SET disabled = ?, token_version = token_version + ? WHERE id = ?",
                (int(disabled), int(disabled), user_id),
            )
            self._log("DISABLE_USER" if disabled else "ENABLE_USER", str(user_id))
            self.conn.execute("COMMIT")
        except Exception:
            self.conn.execute("ROLLBACK")
            raise
        return self.accounts.get(user_id)

    def set_rate(self, code: str, mid: Decimal) -> dict:
        """Correct the latest stored rate of one currency (replaces `seed.py --set-rate`)."""
        code = code.strip().upper()
        if not CODE_RE.match(code) or code == BASE:
            raise ApiError(400, "UNKNOWN_CURRENCY", "Currency must be a 3-letter code other than PLN.",
                           [{"field": "code", "problem": "expected 3 letters, e.g. EUR"}])
        if not mid.is_finite() or mid <= 0 or decimals(mid) > 4:
            raise ApiError(400, "INVALID_RATE", "mid must be > 0 with at most 4 decimal places.",
                           [{"field": "mid", "problem": "must be > 0, max 4 decimals"}])
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            cur = self.conn.execute(
                "UPDATE rates SET mid_e4 = ?, fetched_at = ? WHERE currency = ? AND effective_date = "
                "(SELECT MAX(effective_date) FROM rates WHERE currency = ?)",
                (rate_to_e4(mid), _now_iso(), code, code),
            )
            if cur.rowcount == 0:
                self.conn.execute("ROLLBACK")
                raise ApiError(400, "UNKNOWN_CURRENCY", f"No stored rate for {code}.",
                               [{"field": "code", "problem": "not in NBP table A"}])
            self._log("SET_RATE", code, str(mid))
            self.conn.execute("COMMIT")
        except ApiError:
            raise
        except Exception:
            self.conn.execute("ROLLBACK")
            raise
        row = self.conn.execute(
            "SELECT effective_date, mid_e4 FROM rates WHERE currency = ? ORDER BY effective_date DESC LIMIT 1",
            (code,)).fetchone()
        return {"code": code, "effectiveDate": row["effective_date"], "mid": float(rate_from_e4(row["mid_e4"]))}

    def actions(self, limit: int = 50) -> list[dict]:
        rows = self.conn.execute(
            "SELECT a.id, u.email AS admin, a.action, a.target, a.detail, a.created_at "
            "FROM admin_actions a JOIN users u ON u.id = a.admin_id ORDER BY a.id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [{"id": r["id"], "admin": r["admin"], "action": r["action"], "target": r["target"],
                 "detail": r["detail"], "createdAt": r["created_at"]} for r in rows]
