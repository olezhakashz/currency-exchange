"""Print what the database holds now: orders and balances (Lab 06 evidence).

    python db_state.py            (from backend/, uses DATABASE_PATH from .env)
"""
import sqlite3

from app.config import get_settings

QUERIES = [
    "SELECT request_id, side, currency, amount_minor, seen_rate_e4, rate_used_e4, pln_minor, status, reason, created_at "
    "FROM orders ORDER BY created_at",
    "SELECT u.email, b.currency, b.amount_minor FROM balances b JOIN users u ON u.id = b.user_id "
    "ORDER BY u.email, b.currency",
    "SELECT currency, effective_date, mid_e4 FROM rates WHERE currency = 'EUR' ORDER BY effective_date",
]

if __name__ == "__main__":
    conn = sqlite3.connect(get_settings().database_path)
    for q in QUERIES:
        print(f"$ sqlite> {q}")
        cur = conn.execute(q)
        print(" | ".join(d[0] for d in cur.description))
        for row in cur:
            print(" | ".join(str(v) for v in row))
        print()
