# Requirements

No template was supplied with the assignment, so this file uses a simple
table: ID, requirement, type (read or action), and how to test it.

**Reads** show data and may use a local cache. **Actions** change data
on the server and are only "done" when the server confirms them.

## Offline policy (decision)

While offline the app **blocks** all actions (buy, sell, register)
and **allows** reads from the local cache, clearly labelled as cached.
Reason: an order is only valid at the rate and balance the server confirms,
so a queued offline order could execute at a different rate or overdraw
the wallet later.

## Functional requirements

| ID | Requirement | Type | How to test |
| --- | --- | --- | --- |
| FR1 | The user can register and log in with email and password. | Action | Register a new user, log in, receive a token; wrong password returns an error. |
| FR2 | The app shows a list of current exchange rates (NBP table A) with the rate's effective date. | Read | Open the rates screen; every rate shows a date that matches NBP for that day. |
| FR3 | The user can convert an amount between PLN and a chosen currency using the displayed rate. | Read (local) | 100 PLN to EUR equals 100 / rate, rounded to 2 decimals. |
| FR4 | The user can view the wallet balance in each currency. A new user starts with 1000.00 virtual PLN. | Read | A new user's wallet shows 1000.00 PLN and nothing else. |
| FR5 | The user can buy a foreign currency with PLN at the current server rate. | Action | Buy 100 EUR; PLN decreases by 100 x rate, EUR increases by 100, one order is stored. |
| FR6 | The user can sell a foreign currency for PLN at the current server rate. | Action | Sell 50 EUR; balances change by the expected amounts, one order stored. |
| FR7 | The server rejects a buy or sell if the balance is too low. | Action | Buy more than the balance allows; server returns an error and no balance changes. |
| FR8 | Every action carries a unique request ID created on the phone before sending. | Action | Send the same request ID twice; the server stores one order and returns the same result both times. |
| FR9 | The app can ask the server for the status of an action by request ID. | Read | `GET /orders/{id}` returns `confirmed`, `rejected` or `not_found`. |
| FR10 | The server rejects an order if the rate the user saw differs from the current rate, and returns the new rate. | Action | Send an order with an old rate; server returns "rate changed" with the new rate, nothing executes. |

## Non-functional requirements

| ID | Requirement | How to test |
| --- | --- | --- |
| NFR1 | Every request from the app has a timeout of 10 seconds. | Delay server responses by 15 s; the app shows a timeout message after 10 s. |
| NFR2 | Cached data is always shown with its date and a "cached" label when not fresh from the server. | Go offline, open rates; label and date are visible. |
| NFR3 | Rates older than the latest NBP publication day are marked **stale**. | Use a cache from 2 working days ago; the app shows "stale". |
| NFR4 | While offline, action buttons are disabled and a message explains why, within 1 second of losing the connection. | Turn on airplane mode; buttons disable with a message. |
| NFR5 | A data-changing request is executed by the server **at most once** per request ID. | Send the same order 3 times; the database has one order. |
| NFR6 | Automatic retries for reads: at most 3, with backoff 1 s, 2 s, 4 s. Actions are **not** retried automatically; the app checks status (FR9) instead. | Make the server fail reads twice; the third read succeeds. Make an action time out; the app calls the status endpoint, not POST again. |
| NFR7 | After reconnection, the app refreshes rates and wallet within 5 seconds and resolves any action in "unknown" state. | Reconnect with one order in "checking"; it changes to confirmed or rejected. |
| NFR8 | Balance updates are atomic; two competing actions can't make a balance negative. | Send two sells of the full EUR balance at the same moment; exactly one succeeds. |
| NFR9 | The server caches NBP rates and calls NBP at most once per hour. | Request rates 20 times within an hour; server log shows one NBP call. |
| NFR10 | All traffic between app and server uses HTTPS; actions require a login token. | Call an action without a token; the server returns 401. |
