"""Create the database and fill it with test data.

    python seed.py                 create tables, load sample rates, create the demo user
    python seed.py --reset         delete the database file first (clean start)
    python seed.py --set-rate EUR 4.2710
                                   simulate a new NBP rate for one currency
                                   (used in the demo to show RATE_CHANGED)

The sample rates in data/nbp-table-a-sample.json are simulated values in the
same JSON shape as the real NBP table A response.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from app import db
from app.auth import AuthService
from app.config import ConfigError, get_settings
from app.errors import ApiError
from app.money import rate_to_e4

SAMPLE = Path(__file__).with_name("data") / "nbp-table-a-sample.json"
DEMO_EMAIL = "demo@example.com"


def load_rates(conn, table: dict) -> int:
    fetched = datetime.now(timezone.utc).isoformat(timespec="seconds")
    conn.execute("BEGIN")
    for r in table["rates"]:
        conn.execute(
            "INSERT OR REPLACE INTO rates (currency, effective_date, mid_e4, fetched_at) VALUES (?, ?, ?, ?)",
            (r["code"], table["effectiveDate"], rate_to_e4(Decimal(str(r["mid"]))), fetched),
        )
    conn.execute("COMMIT")
    return len(table["rates"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reset", action="store_true", help="delete the database file first")
    parser.add_argument("--set-rate", nargs=2, metavar=("CODE", "MID"), help="change the latest rate of one currency")
    args = parser.parse_args()

    try:
        settings = get_settings()
    except ConfigError as e:
        print(f"Config error: {e}", file=sys.stderr)
        return 1

    if args.reset and settings.database_path.exists():
        settings.database_path.unlink()
        print(f"Deleted {settings.database_path}")

    conn = db.connect(settings.database_path)
    db.init_schema(conn)

    if args.set_rate:
        code, mid = args.set_rate[0].upper(), Decimal(args.set_rate[1])
        cur = conn.execute(
            "UPDATE rates SET mid_e4 = ?, fetched_at = ? WHERE currency = ? AND effective_date = "
            "(SELECT MAX(effective_date) FROM rates WHERE currency = ?)",
            (rate_to_e4(mid), datetime.now(timezone.utc).isoformat(timespec="seconds"), code, code),
        )
        print(f"{code} latest rate set to {mid}" if cur.rowcount else f"No rate for {code}; run seed first")
        return 0 if cur.rowcount else 1

    table = json.loads(SAMPLE.read_text(encoding="utf-8"))[0]
    n = load_rates(conn, table)
    print(f"Loaded {n} rates for {table['effectiveDate']} from {SAMPLE.name} (simulated data)")

    password = os.environ.get("DEMO_PASSWORD", "")
    if len(password) < 8 or password.startswith("change-me"):
        print("DEMO_PASSWORD not set in backend/.env, so no demo user was created.")
    else:
        auth = AuthService(conn, settings.secret_key, settings.token_ttl_seconds, settings.start_balance_pln)
        try:
            uid = auth.register(DEMO_EMAIL, password)
            print(f"Created demo user {DEMO_EMAIL} (id {uid}) with {settings.start_balance_pln} PLN")
        except ApiError as e:
            if e.code != "EMAIL_TAKEN":
                raise
            print(f"Demo user {DEMO_EMAIL} already exists")

    print(f"Database ready: {settings.database_path}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
