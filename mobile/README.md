# Mobile app (Flutter)

The phone client of the currency exchange project. It talks only to our web
service (`backend/`), over HTTP in development and HTTPS when deployed.

## Requirements

- Flutter 3.35 or newer (tested with 3.47.9, Dart 3.13)
- Android Studio with an emulator, or an Android phone with USB debugging
- The backend running (see `backend/README.md`)

## Run

```bash
cd mobile
flutter pub get
flutter test                 # 22 tests: ApiClient, order screen, session (Lab 07)
```

**Android emulator** (the emulator sees your computer as `10.0.2.2`):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

**Real phone on the same Wi-Fi:** start the backend with
`uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000`, find your
computer's address (`ipconfig` / `ip addr`), then
`flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000`.

The address can also be changed on the login screen. Log in as
`demo@example.com` with `DEMO_PASSWORD` from `backend/.env`, or create an account.

**HTTP vs HTTPS:** plain HTTP is allowed only in debug builds
(`android/app/src/debug/AndroidManifest.xml`, `usesCleartextTraffic`).
A release build accepts only HTTPS, which is what a deployed service uses.

**Browser (optional):** `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000`
needs `CORS_ORIGINS` in `backend/.env` set to the page's address.

## Code

| File | What it does |
| --- | --- |
| `lib/api/api_client.dart` | All HTTP calls. 10 s timeout. Reads are retried up to 3 times when there is no connection; orders are never retried automatically. Sorts every failure into a `ProblemKind`. |
| `lib/api/models.dart` | Rates, wallet, order request/result, `requestId` (UUID v4 made on the phone) |
| `lib/screens/login_screen.dart` | Service address, email, password; log in or create an account; why the last session ended |
| `lib/api/session.dart` | Lab 07: the signed-in user, offline flag, last wallet confirmed by the service. No answer keeps the session; 401 / `ACCOUNT_DISABLED` ends it |
| `lib/screens/home_screen.dart` | Tabs; Admin tab only for role ADMIN; offline banner |
| `lib/screens/account_screen.dart` | Lab 07: who is signed in, own orders (`GET /orders`), log out |
| `lib/screens/admin_screen.dart` | Lab 07: list users, disable / enable (the service checks the role) |
| `lib/screens/rates_screen.dart` | **Read:** `GET /rates` |
| `lib/screens/wallet_screen.dart` | **Read:** `GET /wallet`; offline: last confirmed balances with their time |
| `lib/screens/order_screen.dart` | **Action:** `POST /orders`, and `GET /orders/{id}` when the answer was lost |
| `lib/widgets/status_views.dart` | Loading view and error view (icon, colour and text per kind of problem) |
| `test/` | Unit tests for `ApiClient`, widget tests for the order screen |
| `tool/scenario.js`, `tool/lab07_scenario.js` | The scripts that drove the app for the Lab 06 and Lab 07 screenshots (Playwright, web build) |

Lab 07: what the signed-in user sees when the connection is lost is in
`docs/authorisation.md`, section 4. For the web build use
`flutter build web --no-web-resources-cdn` if the browser can't reach the
CanvasKit CDN.

How each failure is classified, and what the user sees, is in
`docs/mobile-states.md`.
