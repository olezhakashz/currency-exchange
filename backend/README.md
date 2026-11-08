# Backend: web service and database

Python + FastAPI web service with a SQLite database. Lab 05 builds the
foundation: the schema, login, the read path (rates, wallet, order status)
and the write path (buy/sell order).

## Requirements

- Python 3.11 or newer (tested with 3.13)
- No database server: SQLite is built into Python
- For `demo.sh`: bash and curl (Git Bash works on Windows)

## Startup steps (from a fresh clone)

All commands run in the `backend/` folder.

```bash
cd backend

# 1. Virtual environment and packages (versions are pinned)
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 2. Secrets: make your own .env from the example (never commit .env)
cp .env.example .env               # Windows: copy .env.example .env
python -c "import secrets; print(secrets.token_hex(32))"
#    paste the output as SECRET_KEY in .env, and set DEMO_PASSWORD

# 3. Database: create tables, load simulated NBP rates, create the demo user
python seed.py --reset

# 4. Start the service
uvicorn app.main:create_app --factory --port 8000
```

Check it runs: open http://127.0.0.1:8000/health (shows the Git revision)
and http://127.0.0.1:8000/docs (interactive API docs).

If `SECRET_KEY` is missing or still the example value, the service refuses
to start and says what to do.

## Demo and tests

With the service running, in a second terminal (also in `backend/`):

```bash
bash demo.sh | tee ../docs/lab05-demo-output.txt   # end-to-end demo with curl
python -m pytest -v                                 # 28 automated tests
```

The tests use their own temporary database, so they don't touch
`data/exchange.db`.

## Files

| File | What it is |
| --- | --- |
| `app/schema.sql` | Tables and constraints |
| `app/main.py` | HTTP endpoints (controllers) and request models |
| `app/services.py` | `RateService`, `WalletRepository`, `OrderService` (decides if an order succeeded) |
| `app/auth.py` | `AuthService`: password hashing, signed tokens |
| `app/errors.py` | One error format for the whole API |
| `app/money.py` | Exact money maths (integers in the DB) |
| `app/config.py` | Reads settings from environment / `.env` |
| `seed.py` | Creates the database and test data |
| `data/nbp-table-a-sample.json` | Simulated rates in the NBP table A JSON shape |
| `demo.sh` | End-to-end demo script |
| `tests/test_api.py` | Automated tests |
| `.env.example` | Which settings exist (the real `.env` is ignored by Git) |

## Useful commands

```bash
python seed.py --set-rate EUR 4.2710   # pretend NBP published a new EUR rate
python seed.py --reset                 # start again with a clean database
```
