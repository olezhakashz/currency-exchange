// Lab 07 evidence run: drives the real Flutter app (web build, Pixel 7 screen)
// against the running service. Coordinates are CSS pixels for that screen.
// Setup (see docs/auth-evidence.md):
//   backend: python seed.py --reset; uvicorn app.main:create_app --factory --port 8000 >> server.log 2>&1
//            (CORS_ORIGINS=http://127.0.0.1:8080 in .env)
//   app:     flutter build web --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
//            python -m http.server 8080 --bind 127.0.0.1   (in build/web)
//   run:     BACKEND=../../backend SERVER_LOG=server.log ADMIN_PASSWORD=... node lab07_scenario.js
// Needs Node with Playwright and Chromium. Uses lib.js from Lab 06.
const { execSync } = require('child_process');
const { start, shot } = require('./lib');
const BACKEND = process.env.BACKEND || '../../backend';
const LOG = require('path').resolve(process.env.SERVER_LOG || 'server.log');
const BASE = 'http://127.0.0.1:8000';
const mark = (t) => execSync(`echo "=== CLIENT STEP: ${t} ===" >> ${LOG}`);
const sh = (cmd) => execSync(cmd, { encoding: 'utf8' }).trim();
const adminToken = () => sh(`curl -s -X POST ${BASE}/auth/login -H 'Content-Type: application/json' -H 'X-Client: admin-curl' ` +
  `-d '{"email":"admin@example.com","password":"${process.env.ADMIN_PASSWORD}"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])'`);
const tab3 = { rates: 69, wallet: 206, account: 343 };
const tab4 = { rates: 52, wallet: 155, account: 257, admin: 360 };
(async () => {
  const { b, ctx, p } = await start();
  const tap = async (x, y, wait = 600) => { await p.mouse.click(x, y); await p.waitForTimeout(wait); };
  const type = async (x, y, text) => { await tap(x, y, 300); await p.keyboard.press('Control+A'); await p.keyboard.type(text); await p.waitForTimeout(300); };

  mark('1 register: password too short (service answers 400)');
  await tap(206, 364, 800);                        // "No account? Create one"
  await type(206, 191, 'ola@example.com');
  await type(206, 247, 'short');
  await tap(206, 330, 1500); await shot(p, '01-register-validation');

  mark('2 register: valid');
  await type(206, 247, 'ola-secret-1');
  await tap(206, 330, 2500); await shot(p, '02-registered-rates');

  mark('3 account tab (USER: no Admin tab)');
  await tap(tab3.account, 800, 2000); await shot(p, '03-account-user');

  mark('4 buy 100 EUR (own wallet)');
  await tap(tab3.rates, 800, 2000);
  await tap(206, 268, 1000); await tap(206, 288, 2000); await shot(p, '04-order-confirmed');
  await tap(28, 27, 800);

  mark('5 wallet online');
  await tap(tab3.wallet, 800, 2000); await shot(p, '05-wallet-online');

  mark('6 network off: refresh wallet (stays signed in, last confirmed balances)');
  await ctx.setOffline(true);
  await tap(388, 27, 6000); await shot(p, '06-wallet-offline');

  mark('7 network off: account tab');
  await tap(tab3.account, 800, 6000); await shot(p, '07-account-offline');
  await ctx.setOffline(false);

  mark('8 admin disables ola (curl, admin token); app asks the service again');
  const t = adminToken();
  sh(`curl -s -X POST ${BASE}/admin/users/3/disable -H 'X-Client: admin-curl' -H "Authorization: Bearer ${t}" >> ${LOG}; echo >> ${LOG}`);
  await tap(tab3.wallet, 800, 2500); await shot(p, '08-session-ended-disabled');

  mark('9 ola tries to log in again');
  await type(206, 318, 'ola-secret-1');
  await tap(206, 395, 2000); await shot(p, '09-login-disabled');

  mark('10 admin logs in: Admin tab is shown');
  await type(206, 191, 'admin@example.com');
  await type(206, 247, process.env.ADMIN_PASSWORD);
  await tap(206, 315, 2500);
  await tap(tab4.admin, 800, 2500); await shot(p, '10-admin-users');

  mark('11 admin enables ola again (switch changes after the service confirms)');
  await tap(357, 235, 2000); await shot(p, '11-admin-enabled');

  mark('12 admin logs out');
  await tap(tab4.account, 800, 2000);
  await tap(206, 152, 2500); await shot(p, '12-logged-out');

  mark('13 ola logs in again');
  await type(206, 271, 'ola@example.com');
  await type(206, 318, 'ola-secret-1');
  await tap(206, 395, 2500);
  await tap(tab3.account, 800, 2500); await shot(p, '13-ola-back-orders');
  await b.close();
})();
