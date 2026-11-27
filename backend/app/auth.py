"""AuthService: register, login, logout, and who is calling (identification).

Passwords are stored as PBKDF2-SHA256 hashes with a random salt.
Tokens are signed with SECRET_KEY (HMAC-SHA256):

    "<user_id>.<token_version>.<expires>.<signature>"

The signature proves the service made the token, so nobody can change the
user id in it. On every request the service still reads the user row, so:
  - a deleted user, a disabled account or an older token_version is refused
    at once (logout and "disable" work before the token expires);
  - the role comes from the database, never from the token or the request.

What a caller may do with their identity is decided in authz.py.
"""
import base64
import hashlib
import hmac
import re
import secrets
import sqlite3
import time
from dataclasses import dataclass
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


ROLES = ("USER", "ADMIN")


@dataclass(frozen=True)
class Caller:
    """The identified caller of one request."""
    id: int
    email: str
    role: str

    @property
    def is_admin(self) -> bool:
        return self.role == "ADMIN"


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
    def register(self, email: str, password: str, role: str = "USER") -> int:
        """Public registration always passes role USER; only seed.py makes an ADMIN."""
        email = self._check_credentials(email, password)
        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            cur = self.conn.execute(
                "INSERT INTO users (email, password_hash, created_at, role) VALUES (?, ?, ?, ?)",
                (email, hash_password(password), now, role),
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

    def login(self, email: str, password: str) -> tuple[str, Caller]:
        row = self.conn.execute(
            "SELECT id, email, role, password_hash, disabled, token_version FROM users WHERE email = ?",
            (email.strip().lower(),),
        ).fetchone()
        if row is None or not verify_password(password, row["password_hash"]):
            raise ApiError(401, "BAD_CREDENTIALS", "Wrong email or password.")
        if row["disabled"]:
            # Said only after the right password, so it does not reveal which emails exist.
            raise ApiError(403, "ACCOUNT_DISABLED", "This account is disabled. Contact the administrator.")
        return self.make_token(row["id"], row["token_version"]), Caller(row["id"], row["email"], row["role"])

    def logout(self, caller: Caller) -> None:
        """Ends every session of this user: all tokens issued so far stop working."""
        self.conn.execute("UPDATE users SET token_version = token_version + 1 WHERE id = ?", (caller.id,))

    def _sign(self, payload: str) -> str:
        sig = hmac.new(self.key, payload.encode(), hashlib.sha256).digest()
        return base64.urlsafe_b64encode(sig).decode().rstrip("=")

    def make_token(self, user_id: int, token_version: int | None = None) -> str:
        if token_version is None:
            token_version = self.conn.execute(
                "SELECT token_version FROM users WHERE id = ?", (user_id,)).fetchone()["token_version"]
        payload = f"{user_id}.{token_version}.{int(time.time()) + self.ttl}"
        return payload + "." + self._sign(payload)

    def identify(self, authorization: str | None) -> Caller:
        """Who is calling? Raises 401/403 ApiError when the caller can't be trusted."""
        if not authorization or not authorization.startswith("Bearer "):
            raise ApiError(401, "UNAUTHORIZED", "Missing header 'Authorization: Bearer <token>'.")
        token = authorization[len("Bearer "):].strip()
        try:
            user_s, ver_s, exp_s, sig = token.split(".")
            ok = hmac.compare_digest(sig, self._sign(f"{user_s}.{ver_s}.{exp_s}"))
            user_id, version, exp = int(user_s), int(ver_s), int(exp_s)
        except ValueError:
            ok = False
        if not ok:
            raise ApiError(401, "UNAUTHORIZED", "Token is not valid.")
        if exp < time.time():
            raise ApiError(401, "TOKEN_EXPIRED", "Token has expired, log in again.")
        row = self.conn.execute(
            "SELECT id, email, role, disabled, token_version FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        if row is None:
            raise ApiError(401, "UNAUTHORIZED", "User no longer exists.")
        if row["disabled"]:
            raise ApiError(403, "ACCOUNT_DISABLED", "This account is disabled. Contact the administrator.")
        if row["token_version"] != version:
            raise ApiError(401, "TOKEN_REVOKED", "This session was ended (logout). Log in again.")
        return Caller(row["id"], row["email"], row["role"])
