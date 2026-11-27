# Currency Exchange (Mobile Systems project)

## Author

* Oleh (working alone)

## Topic

We chose **currency exchange**. Exchange rates come from the public
National Bank of Poland (NBP) API, which is free and needs no key, so we
can focus on the mobile and network problems instead of collecting data.

## What the system does

A user checks current exchange rates on their phone, converts amounts,
and "buys" or "sells" currency from a virtual wallet (no real money).
The phone works over a wireless network that can be slow or drop.

## Components

|Component|Role|
|-|-|
|Mobile app|Shows rates, converts amounts, sends buy/sell orders, keeps a local cache of the last rates.|
|Web service (backend)|Exposes a REST API to the app, fetches rates from NBP, validates and executes orders, stores wallets.|
|Database|Stores users, wallet balances, transactions, and a copy of the latest rates with their date.|
|External data source|NBP API, `https://api.nbp.pl/api/exchangerates/` (table A, mid rates, published once per working day).|

## Technology choices

|Part|Choice|Why|
|-|-|-|
|Mobile app|Flutter (Dart) *or* Android with Kotlin|One codebase, easy HTTP and local storage.|
|Web service|Python + FastAPI|Short code, automatic API docs.|
|Database|SQLite (dev), PostgreSQL (later, optional)|No setup to start.|
|Local cache on phone|SQLite / shared preferences|Show last rates when offline.|
|Version control|Git + GitHub|Required.|

(Change these if you already know something else; just keep the reason.)

## Repository layout

```
README.md
docs/architecture.md     architecture sketch, data owners
docs/user-journeys.md    normal and broken journeys
docs/risks.md            initial risk list
docs/lab-log.md          short note after each lab
docs/authorisation.md    who may do what, offline signed-in view, evidence (Lab 07)
docs/diagrams/           PlantUML models (use cases, classes, ERD, flows)
backend/                 web service
mobile/                  mobile app
```

## How to run the backend

Short version (details and Windows commands in [backend/README.md](backend/README.md)):

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # then set SECRET_KEY and DEMO_PASSWORD
python seed.py --reset
uvicorn app.main:create_app --factory --port 8000
```

Secrets live only in `backend/.env`, which Git ignores. API endpoints are
described in [docs/api.md](docs/api.md).

## How to run the mobile app

Flutter app in `mobile/` (details in [mobile/README.md](mobile/README.md)).
Start the backend first, then:

```bash
cd mobile
flutter pub get
flutter test                                   # 22 tests
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```

Log in as `demo@example.com` with the `DEMO_PASSWORD` from `backend/.env`,
or create an account on the login screen ("No account? Create one").
`admin@example.com` with `ADMIN_PASSWORD` is the administrator.
What each screen shows while loading, on success and on errors:
[docs/mobile-states.md](docs/mobile-states.md).

## Accounts and access (Lab 07)

Users register and log in; every request that touches a user's data is
identified by its token and checked by the service, whatever the app shows.

| Who | May do |
| --- | --- |
| Visitor (no token) | Register, log in, read exchange rates (public, read-only data) |
| USER | Own account, own wallet, own orders (buy / sell), log out |
| ADMIN | Everything a USER may do on their own wallet, plus: list users, read any account, wallet and orders, disable / enable accounts, correct a rate |

Refused requests get `401` (caller not identified: no token, edited,
expired or revoked) or `403` (identified but not allowed, or account
disabled). When the phone loses the connection the user stays signed in and
sees only what the service last confirmed. Details, the rule table and the
evidence: [docs/authorisation.md](docs/authorisation.md). The API with the
"who may call" column: [docs/api.md](docs/api.md).

## README outline (sections to fill in over the semester)

1. Author
2. Topic and goal
3. Architecture (link to docs/architecture.md)
4. Technology choices and reasons
5. How to run the backend
6. How to run the mobile app
7. API endpoints and access rules
8. Handling connectivity problems (cache, retries, idempotent orders)
9. Tests
10. Known limitations

