# API outline

The mobile app talks only to my web service. The web service is the only
part that talks to NBP. All endpoints use HTTPS and JSON. Endpoints marked
"token" need the header `Authorization: Bearer <token>`.

| Method | Path | Token | Read / action | What it does |
| --- | --- | --- | --- | --- |
| POST | `/auth/register` | no | action | Create a user. The new wallet gets 1000.00 PLN. |
| POST | `/auth/login` | no | action | Returns a token. |
| GET | `/rates` | no | read | Current mid rates with their NBP date and a `stale` flag. |
| GET | `/wallet` | yes | read | Balances of the logged-in user. |
| POST | `/orders` | yes | action | Buy or sell. Runs at most once per `requestId`. |
| GET | `/orders/{requestId}` | yes | read | Status of an order: `CONFIRMED`, `REJECTED` or `NOT_FOUND`. |

## Examples

`GET /rates`

```json
{
  "effectiveDate": "2026-10-30",
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

Answer when it worked:

```json
{ "requestId": "6f1c...1e42", "status": "CONFIRMED", "rateUsed": 4.2650,
  "balances": { "PLN": 573.50, "EUR": 100.00 } }
```

Answer when it didn't:

```json
{ "requestId": "6f1c...1e42", "status": "REJECTED", "reason": "RATE_CHANGED", "currentRate": 4.2710 }
```

Other reasons: `INSUFFICIENT_FUNDS`, `INVALID_AMOUNT`, `UNKNOWN_CURRENCY`.

If the same `requestId` comes again, the server doesn't run the order a
second time. It sends back the answer it saved the first time.

## Status codes

| Code | When |
| --- | --- |
| 200 | OK (also for a repeated `requestId`) |
| 201 | User created |
| 400 | Bad input |
| 401 | Missing or wrong token |
| 404 | Order not found (`GET /orders/{id}`) |
| 409 | Order rejected (rate changed, not enough money) |
| 503 | NBP is down and there are no saved rates at all |

## NBP calls made by the server

`GET https://api.nbp.pl/api/exchangerates/tables/A/?format=json`

The server calls this at most once per hour and saves the result in the
`rates` table.
