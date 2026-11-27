"""Database connection and schema setup."""
import sqlite3
from pathlib import Path

SCHEMA_FILE = Path(__file__).with_name("schema.sql")

# Lab 07: columns added to a table that already exists in a Lab 05/06 database.
# CREATE TABLE IF NOT EXISTS does not add them, so they are added here.
_ADDED_COLUMNS = {
    "users": [
        ("role", "TEXT NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'ADMIN'))"),
        ("disabled", "INTEGER NOT NULL DEFAULT 0 CHECK (disabled IN (0, 1))"),
        ("token_version", "INTEGER NOT NULL DEFAULT 0"),
    ],
}


def connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    # isolation_level=None: we open transactions ourselves with BEGIN IMMEDIATE.
    conn = sqlite3.connect(path, timeout=5, isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_FILE.read_text(encoding="utf-8"))
    for table, columns in _ADDED_COLUMNS.items():
        have = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
        for name, ddl in columns:
            if name not in have:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")
