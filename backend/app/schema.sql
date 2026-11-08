-- Database schema for the currency exchange web service (SQLite).
-- Money is stored as whole numbers to avoid rounding errors:
--   *_minor  = amount in 1/100 of the currency (grosz, cents)
--   *_e4     = exchange rate multiplied by 10 000 (NBP gives 4 decimals)

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    email         TEXT    NOT NULL UNIQUE,
    password_hash TEXT    NOT NULL,
    created_at    TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS balances (
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    currency     TEXT    NOT NULL CHECK (length(currency) = 3),
    amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
    PRIMARY KEY (user_id, currency)
);

CREATE TABLE IF NOT EXISTS rates (
    currency       TEXT    NOT NULL CHECK (length(currency) = 3),
    effective_date TEXT    NOT NULL,          -- YYYY-MM-DD, NBP publication day
    mid_e4         INTEGER NOT NULL CHECK (mid_e4 > 0),
    fetched_at     TEXT    NOT NULL,
    PRIMARY KEY (currency, effective_date)
);

CREATE TABLE IF NOT EXISTS orders (
    request_id    TEXT    PRIMARY KEY,         -- UUID made on the phone
    user_id       INTEGER NOT NULL REFERENCES users(id),
    side          TEXT    NOT NULL CHECK (side IN ('BUY', 'SELL')),
    currency      TEXT    NOT NULL CHECK (length(currency) = 3),
    amount_minor  INTEGER NOT NULL CHECK (amount_minor > 0),
    seen_rate_e4  INTEGER NOT NULL CHECK (seen_rate_e4 > 0),
    rate_used_e4  INTEGER,                     -- NULL when rejected
    pln_minor     INTEGER,                     -- PLN paid or received, NULL when rejected
    status        TEXT    NOT NULL CHECK (status IN ('CONFIRMED', 'REJECTED')),
    reason        TEXT,                        -- RATE_CHANGED / INSUFFICIENT_FUNDS
    response_json TEXT    NOT NULL,            -- answer sent the first time, replayed on repeat
    created_at    TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
