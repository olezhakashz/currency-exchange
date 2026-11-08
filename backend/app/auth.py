"""AuthService: register, login, check token.

Passwords are stored as PBKDF2-SHA256 hashes with a random salt.
Tokens are signed with SECRET_KEY (HMAC-SHA256): "<user_id>.<expires>.<signature>".
They need no table, because the server can check the signature itself.
"""
import base64
import hashlib
import hmac
import re
import secrets
import sqlite3
import time
from datetime import datetime, timezone
from decimal import Decimal

from .errors import ApiError
from .money import to_minor

PBKDF2_ROUNDS = 200_000
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ROUNDS)
    return f"pbkdf2_sha256${PBKDF2_ROUNDS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, rounds, salt_hex, digest_hex = stored.split("$")
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), int(rounds))
    return hmac.compare_digest(digest.hex(), digest_hex)


class AuthService:
    def __init__(self, conn: sqlite3.Connection, secret_key: str, ttl: int, start_balance_pln: str):
        self.conn = conn
        self.key = secret_key.encode()
        self.ttl = ttl
        self.start_balance_minor = to_minor(Decimal(start_balance_pln))

    # ---- input checks at the boundary -------------------------------------
    @staticmethod
    def _check_credentials(email: str, password: str) -> str:
        email = email.strip().lower()
        details = []
        if not EMAIL_RE.match(email) or len(email) > 254:
            details.append({"field": "email", "problem": "must be a valid email address"})
        if not 8 <= len(password) <= 128:
            details.append({"field": "password", "problem": "must be 8 to 128 characters"})
        if details:
            raise ApiError(400, "VALIDATION_ERROR", "Email or password is not acceptable.", details)
        return email

    # ---- operations --------------------------------------------------------
    def register(self, email: str, password: str) -> int:
        email = self._check_credentials(email, password)
        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            cur = self.conn.execute(
                "INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
                (email, hash_password(password), now),
            )
            user_id = cur.lastrowid
            self.conn.execute(
                "INSERT INTO balances (user_id, currency, amount_minor) VALUES (?, 'PLN', ?)",
                (user_id, self.start_balance_minor),
            )
            self.conn.execute("COMMIT")
        except sqlite3.IntegrityError:
            self.conn.execute("ROLLBACK")
            raise ApiError(409, "EMAIL_TAKEN", "An account with this email already exists.",
                           [{"field": "email", "problem": "already registered"}])
        except Exception:
            self.conn.execute("ROLLBACK")
            raise
        return user_id

    def login(self, email: str, password: str) -> str:
        row = self.conn.execute(
            "SELECT id, password_hash FROM users WHERE email = ?", (email.strip().lower(),)
        ).fetchone()
        if row is None or not verify_password(password, row["password_hash"]):
            raise ApiError(401, "BAD_CREDENTIALS", "Wrong email or password.")
        return self.make_token(row["id"])

    def make_token(self, user_id: int) -> str:
        payload = f"{user_id}.{int(time.time()) + self.ttl}"
        sig = hmac.new(self.key, payload.encode(), hashlib.sha256).digest()
        return payload + "." + base64.urlsafe_b64encode(sig).decode().rstrip("=")

    def check_token(self, authorization: str | None) -> int:
        if not authorization or not authorization.startswith("Bearer "):
            raise ApiError(401, "UNAUTHORIZED", "Missing header 'Authorization: Bearer <token>'.")
        token = authorization[len("Bearer "):].strip()
        try:
            user_s, exp_s, sig = token.split(".")
            expected = hmac.new(self.key, f"{user_s}.{exp_s}".encode(), hashlib.sha256).digest()
            expected_s = base64.urlsafe_b64encode(expected).decode().rstrip("=")
            ok = hmac.compare_digest(sig, expected_s)
            user_id, exp = int(user_s), int(exp_s)
        except ValueError:
            ok = False
        if not ok:
            raise ApiError(401, "UNAUTHORIZED", "Token is not valid.")
        if exp < time.time():
            raise ApiError(401, "TOKEN_EXPIRED", "Token has expired, log in again.")
        if self.conn.execute("SELECT 1 FROM users WHERE id = ?", (user_id,)).fetchone() is None:
            raise ApiError(401, "UNAUTHORIZED", "User no longer exists.")
        return user_id
