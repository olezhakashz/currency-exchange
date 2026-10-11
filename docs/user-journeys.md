# User journeys

## Normal journeys

### N1. Check a rate and convert
1. User opens the app on a good connection.
2. App requests today's rates; the server returns them (from its DB copy or NBP).
3. User picks EUR, types 250 PLN, sees the converted amount and the rate date.

### N2. Buy currency
1. User chooses "Buy 100 EUR".
2. App sends the order; the server checks the balance and rate, saves it.
3. App shows "Done" and the new wallet balance.

## Journeys interrupted by connectivity loss

### C1. Lost connection while loading rates (stale data)
1. User opens the app in a train/elevator; the request times out.
2. App shows the cached rates with a clear label: "Offline. Rates from 2026-10-09".
3. Buying is disabled (or warns) because the rate may be out of date.
4. When the connection returns, the app refreshes and removes the label.

### C2. Response lost after sending a buy order (uncertain outcome)
1. User taps "Buy 100 EUR"; the request reaches the server and is executed.
2. The reply is lost on the wireless link; the app times out.
3. The app does not know if the purchase happened. It shows "Checking order...".
4. On reconnect, the app asks `GET /orders/{order_id}`; the server says it is
   confirmed, so the app shows the result. If the app retries the `POST`, the
   same `order_id` means the server does not buy twice.
