"""Service layer: RateService, WalletRepository and OrderService (see classes-server.puml).

OrderService is the only place that decides whether an order succeeded.
Its decision is the row it writes to the `orders` table.
"""
import json
import re
import sqlite3
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo

from .errors import ApiError
from .money import decimals, from_minor, pln_value_minor, rate_from_e4, rate_to_e4, to_minor

WARSAW = ZoneInfo("Europe/Warsaw")
NBP_PUBLISH_TIME = time(12, 30)  # table A is out by about 12:15 Warsaw time
BASE = "PLN"
MAX_ORDER_AMOUNT = Decimal("1000000")
CODE_RE = re.compile(r"^[A-Z]{3}$")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def expected_latest_nbp_day(now: datetime | None = None) -> date:
    """Newest table A that should exist now (weekends skipped, holidays ignored)."""
    now = (now or datetime.now(timezone.utc)).astimezone(WARSAW)
    day = now.date()
    if day.weekday() < 5 and now.time() >= NBP_PUBLISH_TIME:
        return day
    day -= timedelta(days=1)
    while day.weekday() >= 5:
        day -= timedelta(days=1)
    return day


# --------------------------------------------------------------------------
class RateService:
    """Serves the saved copy of NBP rates. (The NBP client is a later lab.)"""

    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def current_rates(self) -> dict:
        rows = self.conn.execute(
            """SELECT r.currency, r.effective_date, r.mid_e4 FROM rates r
               WHERE r.effective_date = (SELECT MAX(effective_date) FROM rates WHERE currency = r.currency)
               ORDER BY r.currency"""
        ).fetchall()
        if not rows:
            raise ApiError(503, "RATES_UNAVAILABLE", "No saved exchange rates yet. Try again later.")
        effective = max(r["effective_date"] for r in rows)
        return {
            "effectiveDate": effective,
            "stale": date.fromisoformat(effective) < expected_latest_nbp_day(),
            "rates": [{"code": r["currency"], "mid": float(rate_from_e4(r["mid_e4"]))} for r in rows],
        }

    def current_rate_e4(self, currency: str) -> int | None:
        row = self.conn.execute(
            "SELECT mid_e4 FROM rates WHERE currency = ? ORDER BY effective_date DESC LIMIT 1", (currency,)
        ).fetchone()
        return row["mid_e4"] if row else None


# --------------------------------------------------------------------------
class WalletRepository:
    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def balances(self, user_id: int) -> dict:
        rows = self.conn.execute(
            "SELECT currency, amount_minor FROM balances WHERE user_id = ? "
            "ORDER BY currency <> 'PLN', currency",
            (user_id,),
        ).fetchall()
        return {r["currency"]: from_minor(r["amount_minor"]) for r in rows}

    def withdraw(self, user_id: int, currency: str, minor: int) -> bool:
        """Take money out only if there is enough. False means 'not enough'."""
        cur = self.conn.execute(
            "UPDATE balances SET amount_minor = amount_minor - ? "
            "WHERE user_id = ? AND currency = ? AND amount_minor >= ?",
            (minor, user_id, currency, minor),
        )
        return cur.rowcount == 1

    def deposit(self, user_id: int, currency: str, minor: int) -> None:
        self.conn.execute(
            "INSERT INTO balances (user_id, currency, amount_minor) VALUES (?, ?, ?) "
            "ON CONFLICT(user_id, currency) DO UPDATE SET amount_minor = amount_minor + excluded.amount_minor",
            (user_id, currency, minor),
        )

    def available_minor(self, user_id: int, currency: str) -> int:
        row = self.conn.execute(
            "SELECT amount_minor FROM balances WHERE user_id = ? AND currency = ?", (user_id, currency)
        ).fetchone()
        return row["amount_minor"] if row else 0


# --------------------------------------------------------------------------
class OrderService:
    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn
        self.rates = RateService(conn)
        self.wallet = WalletRepository(conn)

    # ---- validation at the service boundary --------------------------------
    def validate(self, side: str, currency: str, amount: Decimal, seen_rate: Decimal) -> str:
        currency = currency.strip().upper()
        if not CODE_RE.match(currency):
            raise ApiError(400, "UNKNOWN_CURRENCY", "Currency must be a 3-letter ISO code.",
                           [{"field": "currency", "problem": "expected 3 letters, e.g. EUR"}])
        if currency == BASE:
            raise ApiError(400, "UNKNOWN_CURRENCY", "PLN is the wallet's base currency and cannot be ordered.",
                           [{"field": "currency", "problem": "choose a foreign currency"}])
        if not amount.is_finite() or amount <= 0:
            raise ApiError(400, "INVALID_AMOUNT", "Amount must be greater than 0.",
                           [{"field": "amount", "problem": "must be > 0"}])
        if decimals(amount) > 2:
            raise ApiError(400, "INVALID_AMOUNT", "Amount can have at most 2 decimal places.",
                           [{"field": "amount", "problem": "at most 2 decimal places"}])
        if amount > MAX_ORDER_AMOUNT:
            raise ApiError(400, "INVALID_AMOUNT", "Amount is above the limit of 1 000 000 per order.",
                           [{"field": "amount", "problem": "must be <= 1000000"}])
        if not seen_rate.is_finite() or seen_rate <= 0 or decimals(seen_rate) > 4:
            raise ApiError(400, "INVALID_RATE", "seenRate must be > 0 with at most 4 decimal places.",
                           [{"field": "seenRate", "problem": "must be > 0, max 4 decimals"}])
        if self.rates.current_rate_e4(currency) is None:
            raise ApiError(400, "UNKNOWN_CURRENCY", f"No NBP rate for currency {currency}.",
                           [{"field": "currency", "problem": "not in NBP table A"}])
        return currency

    # ---- write path --------------------------------------------------------
    def execute(self, user_id: int, request_id: str, side: str, currency: str,
                amount: Decimal, seen_rate: Decimal) -> tuple[int, dict, bool]:
        """Returns (http_status, body, replayed)."""
        currency = self.validate(side, currency, amount, seen_rate)
        amount_minor, seen_e4 = to_minor(amount), rate_to_e4(seen_rate)

        # BEGIN IMMEDIATE takes the write lock now, so two orders cannot
        # both read the same balance and both spend it (scenario S11).
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            saved = self.conn.execute("SELECT * FROM orders WHERE request_id = ?", (request_id,)).fetchone()
            if saved is not None:
                self.conn.execute("ROLLBACK")
                return self._replay(saved, user_id, side, currency, amount_minor, seen_e4)

            rate_e4 = self.rates.current_rate_e4(currency)
            pln_minor = pln_value_minor(amount_minor, rate_e4)

            if rate_e4 != seen_e4:
                status, body = 409, {
                    "requestId": request_id, "status": "REJECTED", "reason": "RATE_CHANGED",
                    "currentRate": float(rate_from_e4(rate_e4)),
                }
                self._save(request_id, user_id, side, currency, amount_minor, seen_e4, None, None, body)
            else:
                pay_cur, pay_minor, get_cur, get_minor = (
                    (BASE, pln_minor, currency, amount_minor) if side == "BUY"
                    else (currency, amount_minor, BASE, pln_minor)
                )
                if not self.wallet.withdraw(user_id, pay_cur, pay_minor):
                    status, body = 409, {
                        "requestId": request_id, "status": "REJECTED", "reason": "INSUFFICIENT_FUNDS",
                        "needed": {pay_cur: from_minor(pay_minor)},
                        "available": {pay_cur: from_minor(self.wallet.available_minor(user_id, pay_cur))},
                    }
                    self._save(request_id, user_id, side, currency, amount_minor, seen_e4, None, None, body)
                else:
                    self.wallet.deposit(user_id, get_cur, get_minor)
                    status, body = 200, {
                        "requestId": request_id, "status": "CONFIRMED", "side": side,
                        "currency": currency, "amount": from_minor(amount_minor),
                        "rateUsed": float(rate_from_e4(rate_e4)), "plnAmount": from_minor(pln_minor),
                        "balances": self.wallet.balances(user_id),
                    }
                    self._save(request_id, user_id, side, currency, amount_minor, seen_e4, rate_e4, pln_minor, body)
            self.conn.execute("COMMIT")
            return status, body, False
        except Exception:
            if self.conn.in_transaction:
                self.conn.execute("ROLLBACK")
            raise

    def _save(self, request_id, user_id, side, currency, amount_minor, seen_e4, rate_e4, pln_minor, body):
        self.conn.execute(
            """INSERT INTO orders (request_id, user_id, side, currency, amount_minor, seen_rate_e4,
                                   rate_used_e4, pln_minor, status, reason, response_json, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (request_id, user_id, side, currency, amount_minor, seen_e4, rate_e4, pln_minor,
             body["status"], body.get("reason"), json.dumps(body), _now_iso()),
        )

    def _replay(self, saved, user_id, side, currency, amount_minor, seen_e4):
        same_order = (saved["user_id"], saved["side"], saved["currency"], saved["amount_minor"],
                      saved["seen_rate_e4"]) == (user_id, side, currency, amount_minor, seen_e4)
        if not same_order:
            raise ApiError(409, "REQUEST_ID_REUSED",
                           "This requestId was already used for a different order. Make a new requestId.",
                           [{"field": "requestId", "problem": "already used"}])
        body = json.loads(saved["response_json"])
        return (200 if saved["status"] == "CONFIRMED" else 409), body, True

    # ---- read path ---------------------------------------------------------
    def status(self, user_id: int, request_id: str) -> tuple[int, dict]:
        saved = self.conn.execute(
            "SELECT response_json, created_at FROM orders WHERE request_id = ? AND user_id = ?",
            (request_id, user_id),
        ).fetchone()
        if saved is None:
            # Another user's order also looks NOT_FOUND, so IDs leak nothing.
            return 404, {"requestId": request_id, "status": "NOT_FOUND"}
        body = json.loads(saved["response_json"])
        body["createdAt"] = saved["created_at"]
        return 200, body
