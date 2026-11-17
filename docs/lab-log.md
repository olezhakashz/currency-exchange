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

## Lab 06
- Built the mobile client in Flutter (`mobile/`): log in, rates (read), wallet (read) and buy/sell (data-changing action) over HTTP, talking to the Lab 05 service.
- Every call has a loading, success and error state. A tap only asks for the order; "Confirmed" appears only after the service answers CONFIRMED.
- Errors are told apart: 400 from the service = "Please check the input" (orange, field error under the amount), no answer = "No connection to the service" (red, wifi icon). An order without an answer is "result not known yet", never "failed", and the app asks `GET /orders/{requestId}`; a retry reuses the same `requestId`.
- Small service changes: optional CORS for the web build, one log line per request with the `X-Client` header (docs/design-changes.md rows 16 to 18).
- Evidence: the app ran against the service and database; log and SQL rows in `docs/lab06-demo-output.txt`, screenshots in `docs/screenshots/`, step-by-step in `docs/mobile-states.md`. 13 Flutter tests and 31 backend tests pass.
- Tagged the reviewed version as `lab06`.
- Next: local cache of rates and wallet for offline use, and a connectivity check that disables actions offline.
