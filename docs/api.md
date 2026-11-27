# API outline

The mobile app talks only to my web service. The web service is the only
part that talks to NBP. All endpoints use JSON (HTTPS in production; the
local dev server runs on plain HTTP). Endpoints marked "token" need the
header `Authorization: Bearer <token>`.

Status after Lab 05: all endpoints below are implemented in `backend/`,
except the NBP call, which is replaced by simulated seed data for now.
Lab 06: the Flutter app in `mobile/` uses every endpoint below except
`/auth/register`.
Lab 07: registration, logout, account and admin endpoints added; every
endpoint now has an access rule (column "Who"). Rules are in
`backend/app/authz.py`; the reasons and evidence in
[authorisation.md](authorisation.md).

| Method | Path | Who may call | Read / action | What it does |
| --- | --- | --- | --- | --- |
| GET | `/health` | anyone | read | Service and database are up; shows the Git revision. |
| POST | `/auth/register` | anyone | action | Create a user with role `USER` (the role can't be sent). The new wallet gets 1000.00 PLN. Returns a token. |
| POST | `/auth/login` | anyone | action | Returns a token and the identified user `{id, email, role}`. |
| POST | `/auth/logout` | token | action | Ends **all** sessions of this user: every token issued so far stops working. |
| GET | `/me` | token | read | The caller's own account `{id, email, role, disabled, createdAt}`. |
| GET | `/rates` | anyone | read | Current mid rates with their NBP date and a `stale` flag. Public, read-only. |
| GET | `/wallet` | token | read | Balances of the caller. |
| GET | `/orders` | token | read | The caller's own orders, newest first (max 50). |
| POST | `/orders` | token | action | Buy or sell **on the caller's own wallet**. Runs at most once per `requestId`. |
| GET | `/orders/{requestId}` | token, owner of the order | read | `CONFIRMED`, `REJECTED` or `NOT_FOUND` (also for another user's order). |
| GET | `/users/{id}` | token, that user or ADMIN | read | One account. |
| GET | `/users/{id}/wallet` | token, that user or ADMIN | read | That user's balances. |
| GET | `/users/{id}/orders` | token, that user or ADMIN | read | That user's orders. |
| GET | `/admin/users` | ADMIN | read | All accounts. |
| POST | `/admin/users/{id}/disable` | ADMIN | action | Disable an account; its tokens stop working at once. Not allowed on yourself. |
| POST | `/admin/users/{id}/enable` | ADMIN | action | Enable it again (old tokens stay invalid; the user logs in again). |
| PUT | `/admin/rates/{code}` | ADMIN | action | Correct the latest stored rate, body `{"mid": 4.2710}`. |
| GET | `/admin/actions` | ADMIN | read | Who did which admin action and when (`admin_actions` table). |

The user id an operation works on always comes from the token, never from the
body: `POST /orders` with a `userId` field is refused (400, unknown field).

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

`POST /auth/login` (Lab 07)

```json
{ "token": "3.0.1795819652.mJ0w...", "user": { "id": 3, "email": "ola@example.com", "role": "USER" } }
```

The token is `<user id>.<token version>.<expiry, Unix time>.<HMAC-SHA256 signature>`.
Changing any part breaks the signature. The token version is raised by
logout and by "disable", which is how those end sessions before expiry.

## Headers the app sends (Lab 06)

| Header | Value | Why |
| --- | --- | --- |
| `Authorization` | `Bearer <token>` | Endpoints marked "token" |
| `Content-Type` | `application/json` | Requests with a body |
| `X-Client` | `currency-exchange-mobile/0.7.0 (android)` (or `ios`, `web`) | The service logs it, so the log shows the request came from the app |

The browser (web) build of the app also needs CORS. It is off unless
`CORS_ORIGINS` is set in `backend/.env`; the Android app does not use it.

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
| `UNAUTHORIZED` | 401 | Token missing, wrong or edited; user no longer exists | Go to login |
| `TOKEN_EXPIRED` | 401 | Token too old | Log in again |
| `TOKEN_REVOKED` | 401 | Token from before a logout or a disable (Lab 07) | Log in again |
| `ACCOUNT_DISABLED` | 403 | Account disabled by an admin: any token, and login with the right password (Lab 07) | Go to login, show "account disabled" |
| `FORBIDDEN` | 403 | Signed in, but not allowed: another user's `/users/{id}...`, or `/admin/...` without role ADMIN (Lab 07) | Show "not allowed"; stay signed in |
| `USER_NOT_FOUND` | 404 | Admin asks for a user id that doesn't exist (Lab 07) | Reload the user list |
| `CANNOT_DISABLE_SELF` | 400 | Admin tries to disable their own account (Lab 07) | Bug in the app |
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
| 401 | Caller not identified: missing, wrong, expired or revoked token; wrong password |
| 403 | Caller identified but not allowed (`FORBIDDEN`), or account disabled |
| 404 | Order not found (`GET /orders/{id}`, body `{"status": "NOT_FOUND"}`), or `USER_NOT_FOUND` for an admin |
| 409 | Order rejected (rate changed, not enough money), email taken, `requestId` reused |
| 503 | No saved rates at all |

## NBP calls made by the server

`GET https://api.nbp.pl/api/exchangerates/tables/A/?format=json`

Planned: the server calls this at most once per hour and saves the result in
the `rates` table. In Lab 05 the table is filled by `seed.py` from
`backend/data/nbp-table-a-sample.json`, which has the same JSON shape.
