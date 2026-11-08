# API outline

The mobile app talks only to my web service. The web service is the only
part that talks to NBP. All endpoints use JSON (HTTPS in production; the
local dev server runs on plain HTTP). Endpoints marked "token" need the
header `Authorization: Bearer <token>`.

Status after Lab 05: all endpoints below are implemented in `backend/`,
except the NBP call, which is replaced by simulated seed data for now.

| Method | Path | Token | Read / action | What it does |
| --- | --- | --- | --- | --- |
| GET | `/health` | no | read | Service and database are up; shows the Git revision. |
| POST | `/auth/register` | no | action | Create a user. The new wallet gets 1000.00 PLN. Returns a token. |
| POST | `/auth/login` | no | action | Returns a token. |
| GET | `/rates` | no | read | Current mid rates with their NBP date and a `stale` flag. |
| GET | `/wallet` | yes | read | Balances of the logged-in user. |
| POST | `/orders` | yes | action | Buy or sell. Runs at most once per `requestId`. |
| GET | `/orders/{requestId}` | yes | read | Status of an order: `CONFIRMED`, `REJECTED` or `NOT_FOUND`. |

## Examples

`GET /rates`

```json
{
  "effectiveDate": "2026-11-06",
  "stale": false,
  "rates": [
    { "code": "EUR", "mid": 4.2650 },
    { "code": "USD", "mid": 3.9120 }
  ]
}
```

`POST /orders`

```json
{
  "requestId": "6f1c2a8e-3b4d-4c55-9a1e-2f7b8d0c1e42",
  "side": "BUY",
  "currency": "EUR",
  "amount": 100.00,
  "seenRate": 4.2650
}
```

Answer when it worked (`200`):

```json
{ "requestId": "6f1c...1e42", "status": "CONFIRMED", "side": "BUY", "currency": "EUR",
  "amount": 100.00, "rateUsed": 4.2650, "plnAmount": 426.50,
  "balances": { "PLN": 573.50, "EUR": 100.00 } }
```

Answer when the order was refused (`409`). The refusal is saved like a
confirmed order, so asking again gives the same answer:

```json
{ "requestId": "6f1c...1e42", "status": "REJECTED", "reason": "RATE_CHANGED", "currentRate": 4.2710 }
```

```json
{ "requestId": "6f1c...1e42", "status": "REJECTED", "reason": "INSUFFICIENT_FUNDS",
  "needed": { "PLN": 3838.50 }, "available": { "PLN": 573.50 } }
```

If the same `requestId` comes again with the same order, the server doesn't
run it a second time. It sends back the answer it saved the first time,
with the same status code and the header `Idempotent-Replayed: true`.

## Error format

Every error that is not an order result has the same shape. The app reads
`code`; `message` is for people; `details` lists the fields that are wrong.

```json
{ "error": { "code": "INVALID_AMOUNT",
             "message": "Amount must be greater than 0.",
             "details": [ { "field": "amount", "problem": "must be > 0" } ] } }
```

| Code | HTTP | When | What the app should do |
| --- | --- | --- | --- |
| `VALIDATION_ERROR` | 400 | Field missing, wrong type, unknown field, bad `side` or `requestId` | Fix the form (show `details`) |
| `MALFORMED_JSON` | 400 | Body is not JSON | Bug in the app |
| `INVALID_AMOUNT` | 400 | Amount ≤ 0, more than 2 decimals, or over 1 000 000 | Show "check the amount" |
| `INVALID_RATE` | 400 | `seenRate` ≤ 0 or more than 4 decimals | Reload rates |
| `UNKNOWN_CURRENCY` | 400 | Not 3 letters, PLN, or not in table A | Reload rates |
| `UNAUTHORIZED` | 401 | Token missing or wrong | Go to login |
| `TOKEN_EXPIRED` | 401 | Token too old | Log in again |
| `BAD_CREDENTIALS` | 401 | Wrong email or password at login | Show "wrong email or password" |
| `EMAIL_TAKEN` | 409 | Register with an existing email | Show "already registered" |
| `REQUEST_ID_REUSED` | 409 | Same `requestId`, different order | Make a new `requestId` |
| `RATES_UNAVAILABLE` | 503 | No saved rates at all | Show cached rates, try later |
| `NOT_FOUND`, `METHOD_NOT_ALLOWED` | 404, 405 | Wrong URL or method | Bug in the app |
| `INTERNAL_ERROR` | 500 | Unexpected server error (no stack trace is sent) | Retry reads; check order status |

## Status codes

| Code | When |
| --- | --- |
| 200 | OK, order confirmed (also for a repeated `requestId`) |
| 201 | User created |
| 400 | Bad input (nothing is saved) |
| 401 | Missing or wrong token, wrong password |
| 404 | Order not found (`GET /orders/{id}`, body `{"status": "NOT_FOUND"}`) |
| 409 | Order rejected (rate changed, not enough money), email taken, `requestId` reused |
| 503 | No saved rates at all |

## NBP calls made by the server

`GET https://api.nbp.pl/api/exchangerates/tables/A/?format=json`

Planned: the server calls this at most once per hour and saves the result in
the `rates` table. In Lab 05 the table is filled by `seed.py` from
`backend/data/nbp-table-a-sample.json`, which has the same JSON shape.
