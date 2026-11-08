# Design changes since M1 (tag `part1`, commit 9c29997)

M1 is the Part 1 design report (Lab 04). These are the places where the
code written in Lab 05 differs from that design, and why.

| # | Area | M1 design | Now (Lab 05) | Why |
| --- | --- | --- | --- | --- |
| 1 | Money in the database | `DECIMAL(12,2)` and `DECIMAL(10,4)` | Whole numbers: `amount_minor` (1/100 units) and `*_e4` (rate × 10 000) | SQLite has no exact decimal type; it would store floats and lose grosze. Integers are exact. The API still uses normal decimals. |
| 2 | `orders` table | No copy of the answer | New column `response_json` | A repeated `requestId` must get exactly the first answer (N5), including the balances at that time. Rebuilding it later would show today's balances. |
| 3 | `orders` table | Only rate used | New column `pln_minor` | Stores how many PLN were paid or received, so an order can be checked without recomputing rounding. |
| 4 | `orders` CHECKs, `balances` CHECK | `amount >= 0` as a note | Real `CHECK` constraints (`amount_minor >= 0`, `side IN ...`, `status IN ...`) | The database itself refuses a negative balance even if the code had a bug (N8). |
| 5 | Dates and times | `DATE`, `TIMESTAMP` | ISO-8601 `TEXT` | SQLite stores dates as text anyway; ISO text sorts correctly. |
| 6 | Tokens | Not specified (no table) | Signed tokens (HMAC-SHA256 with `SECRET_KEY`), 24 h expiry | No token table needed; the secret stays in `.env`, out of Git. |
| 7 | Input errors | Reasons `INVALID_AMOUNT`, `UNKNOWN_CURRENCY` listed next to order rejections | Bad input gives `400` with one error format `{"error": {"code", "message", "details"}}` and is **not** saved as an order. Only `RATE_CHANGED` and `INSUFFICIENT_FUNDS` are saved as `REJECTED` (409). | A typo in the request is not an order. The app can fix the input and try again with the same `requestId`. |
| 8 | New error codes | Not specified | `VALIDATION_ERROR`, `MALFORMED_JSON`, `INVALID_RATE`, `UNAUTHORIZED`, `TOKEN_EXPIRED`, `BAD_CREDENTIALS`, `EMAIL_TAKEN`, `REQUEST_ID_REUSED`, `RATES_UNAVAILABLE`, `INTERNAL_ERROR` | The app needs a stable code for each case to show the right message (see `docs/api.md`). |
| 9 | Repeated `requestId` | Always `200` | Same status as the first answer (200 or 409) plus header `Idempotent-Replayed: true`. Same `requestId` with a *different* order gives `409 REQUEST_ID_REUSED`. | A refused order must stay refused when repeated; a reused ID must not hide a different order. |
| 10 | `GET /orders/{id}` of another user | Not specified | `404 NOT_FOUND`, same as an unknown ID | Doesn't leak other users' order IDs. |
| 11 | New endpoint | None | `GET /health` (database check and Git revision) | Easy startup check, and ties the demo to a Git revision. |
| 12 | NBP client | Server fetches table A at most once per hour | Not yet: `rates` is filled from `data/nbp-table-a-sample.json` (simulated, same JSON shape) | Lab 05 asks for the service and database foundation with test data; the NBP client is the next step and can write into the same table. |
| 13 | Stale flag | "older than the latest NBP publication day" | Computed: newest expected table is today after 12:30 Warsaw time on weekdays, otherwise the previous weekday. Holidays are ignored. | Needed a concrete rule to code. Holidays can make it say "stale" when it isn't; fine for now. |
| 14 | Concurrency | "one database transaction" | `BEGIN IMMEDIATE` (write lock before reading the balance) and `UPDATE ... WHERE amount_minor >= ?` | Two orders at the same time cannot both spend the same money (S11). Tested with 4 parallel orders. |
| 15 | Order limits | Not specified | Amount > 0, at most 2 decimals, at most 1 000 000; `seenRate` at most 4 decimals; PLN cannot be ordered | Concrete boundary rules for validation. |

The ERD source `docs/diagrams/erd.puml` is updated to match the real
schema (`backend/app/schema.sql`). `docs/api.md` is updated with the error
format and codes.
