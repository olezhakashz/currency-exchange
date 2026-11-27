# Registration, login and authorisation (Lab 07)

## 1. Registration and login

| Step | Request | What the service does |
| --- | --- | --- |
| Register | `POST /auth/register {email, password}` | Checks the email and 8 to 128 characters of password, stores a PBKDF2-SHA256 hash with a random salt, creates the wallet (1000.00 PLN), role **USER**. A `role` field in the body is refused (400). |
| Log in | `POST /auth/login {email, password}` | Wrong email or password: `401 BAD_CREDENTIALS` (the same for both, so emails can't be probed). Right password on a disabled account: `403 ACCOUNT_DISABLED`. Otherwise a token and `{id, email, role}`. |
| Log out | `POST /auth/logout` | Raises the user's `token_version`, so every token issued so far is refused. |

Administrators are not made through the API. `seed.py` creates
`admin@example.com` when `ADMIN_PASSWORD` is set in `backend/.env`, and
`python seed.py --make-admin EMAIL` promotes an existing user.

## 2. How the service identifies the caller

Each protected request carries `Authorization: Bearer <id>.<version>.<expiry>.<signature>`.
`AuthService.identify()` (backend/app/auth.py) does, in this order:

1. No header, wrong format, or a signature that does not match (any edited part, for example another user id): `401 UNAUTHORIZED`.
2. Expiry passed (24 h): `401 TOKEN_EXPIRED`.
3. Reads the user row. User gone: `401 UNAUTHORIZED`. Account disabled: `403 ACCOUNT_DISABLED`. Token version older than the row's: `401 TOKEN_REVOKED`.
4. Returns `Caller(id, email, role)`. The **role comes from the database**, so a change of role or a disable works on the next request.

The secret that signs tokens (`SECRET_KEY`) is only in `backend/.env`.

## 3. What each caller may do

Every rule is in `backend/app/authz.py`, and every endpoint applies one before
it reads or changes data. Picture: `docs/diagrams/flow-auth.png`.

| Data | Endpoints | Visitor (no token) | USER | ADMIN | Refusal |
| --- | --- | --- | --- | --- | --- |
| Rates | `GET /rates` | read | read | read; correct with `PUT /admin/rates/{code}` | USER on `PUT`: 403 `FORBIDDEN` |
| Own account | `GET /me`, `POST /auth/logout` | no | yes | yes | 401 |
| Accounts by id | `GET /users/{id}` | no | only own id | any | 403 `FORBIDDEN` (same answer for ids that don't exist) |
| Wallets | `GET /wallet`, `GET /users/{id}/wallet` | no | only own | any (read only) | 401 / 403 |
| Orders ("reservations") | `POST /orders`, `GET /orders`, `GET /orders/{requestId}`, `GET /users/{id}/orders` | no | create and read only own; the wallet is always the token's | read any via `/users/{id}/orders`; trade only on own wallet | 401; another user's order: 404 `NOT_FOUND`; body with `userId`: 400 |
| Administration | `/admin/users`, `/admin/users/{id}/disable`, `/enable`, `/admin/actions` | no | **no** | yes; not disable self | 403 `FORBIDDEN`; self: 400 `CANNOT_DISABLE_SELF` |

Nobody, not even an admin, can buy or sell on someone else's wallet: there is
no endpoint for it, and `POST /orders` takes the wallet from the token.

**Hidden controls are not the protection.** The app shows the Admin tab only
to admins, but the service checks the role on every `/admin/...` call. The
demo calls those endpoints with curl and a USER token and gets 403, with no
row changed (demo R7). `test_every_protected_route_refuses_anonymous_caller`
walks every route of the app, so a new endpoint without a check fails the test.

## 4. The signed-in view during connection loss

The rule: **only an answer from the service can end a session or confirm an
operation.** The phone never invents either.

| Situation | What the app does | Why |
| --- | --- | --- |
| No connection or timeout on any request | Stays signed in. Grey banner on every tab: "Offline. Still signed in as ola@example.com. Balances are from 22:58:58. Orders get a result only when the service answers." (screenshots 06, 07) | A lost network says nothing about the account. Logging the user out would lose the order screen and its `requestId`. |
| Wallet while offline | Shows the last balances **the service** confirmed (from `GET /wallet` or a CONFIRMED order answer), titled "Last confirmed balances" in orange, greyed numbers, with the time and "Orders sent since then may not be in them" (06). If nothing was confirmed yet, it shows the "No connection" error instead of zeros. | Old but true data, clearly labelled, is better than an empty screen; it is never adjusted on the phone. |
| Order while offline | As in Lab 06: "No connection: result not known yet", then `GET /orders/{requestId}`. Never "Confirmed", never "Failed". | The order may or may not have arrived. |
| Account tab while offline | Shows who is signed in (kept on the phone); "My orders" shows the "No connection" error and "Orders can only be listed when the service answers" (07). | The order list is service data. |
| Admin switch while offline | The switch doesn't move; message "No connection: the change was not confirmed". | Same rule for admin actions. |
| Service answers 401 (expired, revoked) or 403 `ACCOUNT_DISABLED` | Session ends: token dropped, back to login with the reason, for example "Your account has been disabled by an administrator." (08) | The service has said this token is no longer accepted. |
| Service answers 403 `FORBIDDEN` | "Not allowed for your account. Nothing was changed." The user stays signed in. | The caller is fine; this one action isn't allowed. |
| Logout while offline | The phone forgets the token and says: "You are logged out on this phone. There was no connection, so the service was not told; the old session ends on the service when its token expires." | Honest: the service could not revoke it. |
| An order's answer was lost, then the session expired | After logging in again, "My orders" on the Account tab (`GET /orders`) shows whether it was executed. Orders belong to the user, not the token. | |

The session lives in memory (`mobile/lib/api/session.dart`); closing the app
logs out. Keeping the token and the last data on disk is the next lab
(design change 26).

## 5. Evidence: valid and rejected access paths

`backend/tests/test_lab07.py` (23 tests), `docs/lab07-demo-output.txt`
(curl, `bash backend/demo_auth.sh`), `docs/lab07-app-run.txt` (service log
and database rows while the app ran) and `docs/screenshots/lab07/`.

| # | Path | Result | Test | Demo / app |
| --- | --- | --- | --- | --- |
| V1 | Rates without token | 200 | `test_rates_are_read_from_database` | demo V1 |
| V2 | Register, then log in | 201, 200 with `{id, email, role: USER}` | `test_register_then_login_returns_identity` | demo V2, V3; screenshots 02, 03 |
| V3 | Own account, wallet, wallet by own id | 200 | `test_user_sees_own_account_and_wallet_by_id` | demo V4; screenshot 05 |
| V4 | Order on own wallet, list own orders | 200 | `test_orders_are_listed_and_visible_only_to_their_owner` | demo V5; screenshots 04, 13 |
| V5 | Admin lists users, reads another wallet, disables / enables, corrects a rate | 200 | `test_admin_can_read_any_account_and_wallet`, `test_admin_disables_...`, `test_admin_sets_rate_...` | demo V6, R10; screenshots 10, 11 |
| R1 | Any protected endpoint without token | 401 `UNAUTHORIZED` | `test_every_protected_route_refuses_anonymous_caller` | demo R1 |
| R2 | Token with the user id edited, or expiry extended | 401 `UNAUTHORIZED` | `test_forged_or_edited_token_is_refused` | demo R2 |
| R3 | Expired token | 401 `TOKEN_EXPIRED` | `test_expired_token` | |
| R4 | USER reads another user's account / wallet / orders by id | 403 `FORBIDDEN` | `test_user_cannot_read_another_users_records` (3 cases) | demo R3 |
| R5 | Order body names another wallet (`userId`) | 400, nothing saved | `test_order_body_cannot_name_another_wallet` | demo R4 |
| R6 | Another user's order by `requestId`, or re-sending it | 404 `NOT_FOUND` / 409 `REQUEST_ID_REUSED`, no balances shown | `test_orders_are_listed_and_visible_only_to_their_owner` | demo R5 |
| R7 | Register with `"role": "ADMIN"` | 400 | `test_registration_cannot_choose_admin_role` | demo R6 |
| R8 | USER calls each admin endpoint directly | 403 `FORBIDDEN`, rate and admin log unchanged | `test_normal_user_cannot_use_admin_functions` (5 cases) | demo R7 |
| R9 | Wrong password | 401 `BAD_CREDENTIALS` | `test_login` | demo R8; screenshot 01 shows a 400 at registration |
| R10 | Token after logout | 401 `TOKEN_REVOKED` | `test_logout_revokes_tokens` | demo R9; screenshot 12 |
| R11 | Disabled account: unexpired token and login | 403 `ACCOUNT_DISABLED`; old token stays revoked after enable | `test_admin_disables_account_and_its_token_stops_at_once` | demo R10; screenshots 08, 09 |
| R12 | Admin demoted in the database, same token | 403 on the next request | `test_role_comes_from_database_not_token` | |
| R13 | Admin disables self | 400 `CANNOT_DISABLE_SELF` | `test_admin_cannot_disable_self` | |

### App run (screenshots in `docs/screenshots/lab07/`)

The Flutter web build at Pixel 7 size in headless Chromium, driven by
`mobile/tool/lab07_scenario.js`, against the real service and database.
Log and SQL rows: [lab07-app-run.txt](lab07-app-run.txt).

| Step | Screenshot | Service log |
| --- | --- | --- |
| 1 Create account, password "short" | `01-register-validation` (field error from the service) | `POST /auth/register ... as anonymous -> 400` |
| 2 Create account `ola@example.com` | `02-registered-rates` | `-> 201`, `GET /me ... as user 3 USER -> 200` |
| 3 Account tab: USER, no Admin tab | `03-account-user` | `GET /orders ... as user 3 USER -> 200` |
| 4 Buy 100 EUR | `04-order-confirmed` | `POST /orders ... as user 3 USER -> 200` |
| 5 Wallet | `05-wallet-online` | `GET /wallet -> 200` |
| 6 Network off, refresh wallet | `06-wallet-offline` (banner, last confirmed balances) | no line: nothing reached the service |
| 7 Network off, Account tab | `07-account-offline` (still signed in) | no line |
| 8 Admin disables ola (curl); app asks again | `08-session-ended-disabled` | `POST /admin/users/3/disable ... as user 2 ADMIN -> 200`, then `GET /wallet ... -> 403` |
| 9 Ola logs in | `09-login-disabled` | `POST /auth/login -> 403` |
| 10 Admin logs in, Admin tab | `10-admin-users` | `GET /admin/users ... as user 2 ADMIN -> 200` |
| 11 Admin enables ola | `11-admin-enabled` (switch moved after the answer) | `POST /admin/users/3/enable -> 200` |
| 12 Admin logs out | `12-logged-out` | `POST /auth/logout -> 200` |
| 13 Ola logs in again, her order is there | `13-ola-back-orders` | `GET /orders ... as user 3 USER -> 200` |

In the log, "as anonymous" means no caller was accepted: there was no token,
or the token was refused before the request ran (step 8).

## 6. Known limitations

- Logout ends all sessions of the user (one `token_version` per user), not only this phone's.
- No limit on login attempts yet (brute force); would be a counter per email and IP.
- Tokens are bearer tokens: anyone holding one can use it until it expires or is revoked, so release builds must use HTTPS (Lab 06).
- The token and last confirmed wallet are kept only in memory.
- Admins can read any wallet. A real exchange would log those reads too; we log only changes.
