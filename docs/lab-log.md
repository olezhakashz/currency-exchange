# Lab log

## Lab 01
- Working alone; chose the currency exchange topic (NBP API).
- Created the repository, wrote README, architecture sketch, user journeys, risks.
- Next: start the web service and fetch rates from NBP.

## Lab 02
- Wrote functional and non-functional requirements (docs/requirements.md).
- Wrote the network-scenario matrix (docs/network-scenarios.md).
- Decision: actions are blocked offline, reads come from a labelled cache.
- Next: start the web service and the rates endpoint.

## Lab 03
- Drew use cases, classes for the app and the server, and three flows (read, buy, lost reply) in PlantUML.
- Matched every requirement to a use case and a class.
- Made the project smaller: dropped rate history, top up and transaction history, and updated the Lab 02 requirements to match.
- Next: start the server and get rates from NBP.

## Lab 04
- Wrote the Part 1 design report from the course template (docs/report.pdf, docx is the editable version).
- Added the ERD and an architecture diagram in PlantUML, and an API outline (docs/api.md).
- Tagged the version shown for review as `part1`.
- Next: start coding the web service (rates endpoint and NBP client).

## Lab 05
- Built the web service (FastAPI) and the database (SQLite) in `backend/`.
- Schema in `backend/app/schema.sql`: users, balances, orders, rates, with CHECK constraints so a balance can't go below zero.
- Read path: `GET /rates`, `GET /wallet`, `GET /orders/{requestId}`. Write path: `POST /orders` (buy/sell), balances and order saved in one transaction, at most once per `requestId`.
- Input is checked at the service boundary; every error has a `code` the app can use (docs/api.md).
- Test data: simulated NBP table A in `backend/data/`, a demo user made by `seed.py`. Secrets only in `backend/.env` (ignored by Git), `.env.example` committed.
- Demo output in `docs/lab05-demo-output.txt`; 28 automated tests pass.
- Design changes since M1 are in `docs/design-changes.md`.
- Tagged the reviewed version as `lab05`.
- Next: NBP client that refreshes the rates table at most once per hour.
