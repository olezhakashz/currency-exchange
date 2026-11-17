# Mobile client: screens, states and evidence (Lab 06)

The app has two read screens and one data-changing action, all over HTTP to
the web service (`mobile/lib/api/api_client.dart`):

| Screen | Request | Kind |
| --- | --- | --- |
| Rates | `GET /rates` | read |
| Wallet | `GET /wallet` (token) | read |
| Buy / sell | `POST /orders` (token), then `GET /orders/{requestId}` if the answer is lost | action |

## How a failure is classified

`ApiClient` turns every answer, or missing answer, into one of these. The
screens switch on it, so a wrong input never looks like a network problem.

| Kind | When | Reached the service? | What the user sees |
| --- | --- | --- | --- |
| `validation` | Service answered **400** (`INVALID_AMOUNT`, `VALIDATION_ERROR`, ...) | yes | Orange "Please check the input", the field error under the amount box, "Nothing was saved" |
| `noConnection` | No HTTP answer at all: offline, wrong address, server down | no | Red "No connection to the service" with a Wi-Fi icon and "Try again" |
| `timeout` | No answer within 10 s | unknown | "The service did not answer in time" |
| `auth` | 401 | yes | "Please log in again" |
| `conflict` | 409 with an error body (`REQUEST_ID_REUSED`) | yes | "The service refused the request" |
| `server` | 5xx | yes | "The service has a problem" |

An order refused by the rules (409 `RATE_CHANGED`, `INSUFFICIENT_FUNDS`) is
not an error: it is a saved order result with status `REJECTED`.

## Order screen states

A tap only asks for the order. "Confirmed" is shown only when the service
answers `CONFIRMED`.

| State | Shown as | Next |
| --- | --- | --- |
| editing | Form, button "Buy 100.00 EUR" | tap |
| sending | Spinner "Sending order...", button and fields disabled (no double tap, S13) | answer |
| confirmed | Green "Confirmed by the service", PLN paid, wallet from the answer | "New order" |
| rejected | Orange "Rate changed" (with new rate) or "Not enough money" (needed / available) | "Use new rate" / "Change the order" |
| invalid | Orange "Please check the input" + field error | fix and tap again |
| unknown | Red "No connection to the service: result not known yet" | the app checks status once by itself, then "Check order status" |
| checking | "Checking order..." (`GET /orders/{id}`) | confirmed / rejected / not executed |
| not executed | "The order never reached the service. Nothing was bought or sold." | "Send the same order again" (same `requestId`, so it can't run twice) |

## Evidence run

The app (Flutter web build at Pixel 7 size, in headless Chromium, driven by
`mobile/tool/scenario.js`) used the real Lab 05 service and SQLite database.
Delays of 1.5 s were added in front of some requests so the loading states
stay on screen long enough to capture. The network was switched off in the
browser for steps 6 and 10. Full log and SQL output:
[lab06-demo-output.txt](lab06-demo-output.txt).

| Step | Screenshot | Service log | Database |
| --- | --- | --- | --- |
| 1 Log in | `01-login` | `POST /auth/login -> 200` | |
| Rates loading, then shown | `02-rates-loading`, `03-rates-success` | `GET /rates -> 200` | rates table, 2026-11-06 (marked stale: sample data) |
| 2 Wallet before | `04-wallet-loading`, `05-wallet-before` | `GET /wallet -> 200` | PLN 1000.00 |
| 3 Buy 100 EUR | `06-order-form`, `07-order-sending`, `08-order-confirmed` | `POST /orders -> 200` | order `4cbc74c3` CONFIRMED, 426.50 PLN |
| 4 Wallet after | `09-wallet-after` | `GET /wallet -> 200` | PLN 573.50, EUR 100.00 |
| 5 Amount 0.001 | `10-order-validation` | `POST /orders -> 400` | nothing saved (no row) |
| 6 Network off, buy 50 EUR | `11-order-no-connection` | no line: the request never left the phone | nothing saved |
| 7 Network back, check status | `12-order-not-executed` | `GET /orders/e8a941cd... -> 404` | |
| 8 Send the same order again | `13-order-confirmed-after-retry` | `POST /orders -> 200` | order `e8a941cd` CONFIRMED, exactly one row |
| 9 New EUR rate 4.2710, user still sees 4.2650 | `14-order-rate-changed` | `POST /orders -> 409` | order REJECTED, `RATE_CHANGED` |
| 10 Network off, refresh rates | `15-rates-loading-offline`, `16-rates-no-connection` | no line | |
| 11 Network back, refresh | `17-rates-refreshed` (EUR 4.2710) | `GET /rates -> 200` | |
| 12 Buy 900 EUR | `18-order-insufficient-funds` | `POST /orders -> 409` | order REJECTED, `INSUFFICIENT_FUNDS` |
| 13 Final wallet | `19-wallet-final` | `GET /wallet -> 200` | PLN 360.25, EUR 150.00 |

Steps 5 and 6 are the two cases the lab asks to tell apart: in step 5 the
service answered and refused the input (orange, field error, a 400 in the
log); in step 6 nothing reached the service (red, Wi-Fi icon, no log line),
and the app says the result is unknown instead of "failed".

The final balances match the stored orders: 1000.00 - 426.50 - 213.25 = 360.25 PLN
and 100 + 50 = 150 EUR.
