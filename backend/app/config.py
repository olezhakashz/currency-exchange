"""Settings read from environment variables (and from backend/.env if it exists).

The real .env file is never committed. backend/.env.example shows which
variables exist; copy it to backend/.env and fill in your own values.
"""
import os
from dataclasses import dataclass
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent


def _load_env_file(path: Path) -> None:
    """Very small .env reader: KEY=VALUE lines, # comments. Real env vars win."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


@dataclass(frozen=True)
class Settings:
    database_path: Path
    secret_key: str
    token_ttl_seconds: int
    start_balance_pln: str


class ConfigError(RuntimeError):
    pass


def get_settings() -> Settings:
    _load_env_file(BACKEND_DIR / ".env")

    secret = os.environ.get("SECRET_KEY", "")
    if len(secret) < 32 or secret.startswith("change-me"):
        raise ConfigError(
            "SECRET_KEY is missing or still the example value. "
            "Copy backend/.env.example to backend/.env and set a random key "
            "(python -c \"import secrets; print(secrets.token_hex(32))\")."
        )

    db_path = Path(os.environ.get("DATABASE_PATH", "data/exchange.db"))
    if not db_path.is_absolute():
        db_path = BACKEND_DIR / db_path

    return Settings(
        database_path=db_path,
        secret_key=secret,
        token_ttl_seconds=int(os.environ.get("TOKEN_TTL_SECONDS", "86400")),
        start_balance_pln=os.environ.get("START_BALANCE_PLN", "1000.00"),
    )
