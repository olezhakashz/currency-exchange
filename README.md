# Currency Exchange (Mobile Systems project)

## Author

- Oleh (working alone, agreed with the teacher)

## Topic

We chose **currency exchange**. Exchange rates come from the public
National Bank of Poland (NBP) API, which is free and needs no key, so we
can focus on the mobile and network problems instead of collecting data.

## What the system does

A user checks current exchange rates on their phone, converts amounts,
and "buys" or "sells" currency from a virtual wallet (no real money).
The phone works over a wireless network that can be slow or drop.

## Components

| Component | Role |
| --- | --- |
| Mobile app | Shows rates, converts amounts, sends buy/sell orders, keeps a local cache of the last rates. |
| Web service (backend) | Exposes a REST API to the app, fetches rates from NBP, validates and executes orders, stores wallets. |
| Database | Stores users, wallet balances, transactions, and a copy of the latest rates with their date. |
| External data source | NBP API, `https://api.nbp.pl/api/exchangerates/` (table A, mid rates, published once per working day). |

## Technology choices

| Part | Choice | Why |
| --- | --- | --- |
| Mobile app | Flutter (Dart) *or* Android with Kotlin | One codebase, easy HTTP and local storage. |
| Web service | Python + FastAPI | Short code, automatic API docs. |
| Database | SQLite (dev), PostgreSQL (later, optional) | No setup to start. |
| Local cache on phone | SQLite / shared preferences | Show last rates when offline. |
| Version control | Git + GitHub | Required. |

(Change these if you already know something else; just keep the reason.)

## Repository layout

```
README.md
docs/architecture.md     architecture sketch, data owners
docs/user-journeys.md    normal and broken journeys
docs/risks.md            initial risk list
docs/lab-log.md          short note after each lab
backend/                 web service
mobile/                  mobile app
```

## README outline (sections to fill in over the semester)

1. Author
2. Topic and goal
3. Architecture (link to docs/architecture.md)
4. Technology choices and reasons
5. How to run the backend
6. How to run the mobile app
7. API endpoints
8. Handling connectivity problems (cache, retries, idempotent orders)
9. Tests
10. Known limitations
