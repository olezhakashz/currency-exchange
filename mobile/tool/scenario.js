// Lab 06 evidence run: drives the real Flutter app (web build, Pixel 7 screen)
// against the running service. Coordinates are CSS pixels for that screen.
// Setup (see docs/mobile-states.md):
//   backend: python seed.py --reset; CORS_ORIGINS=http://127.0.0.1:8080 uvicorn ... >> server.log
//   app:     flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8000
//            python -m http.server 8080 --bind 127.0.0.1   (in build/web)
//   run:     BACKEND=../../backend SERVER_LOG=server.log DEMO_PASSWORD=... node scenario.js
// Needs Node with Playwright and Chromium.
const { execSync } = require('child_process');
const { start, shot } = require('./lib');
const BACKEND = process.env.BACKEND || '../../backend';
const LOG = require('path').resolve(process.env.SERVER_LOG || 'server.log');
const mark = (t) => execSync(`echo "=== CLIENT STEP: ${t} ===" >> ${LOG}`);
(async () => {
  const { b, ctx, p } = await start();
  const tap = async (x, y, wait = 400) => { await p.mouse.click(x, y); await p.waitForTimeout(wait); };
  const setAmount = async (v) => { await p.mouse.click(200, 200, { clickCount: 3 }); await p.keyboard.press('Control+A'); await p.keyboard.type(v); await p.waitForTimeout(300); };

  mark('1 login'); await shot(p, '01-login');
  await tap(200, 247); await p.keyboard.type(process.env.DEMO_PASSWORD || '');
  p.delayMs = 1500;
  await tap(200, 315, 1700);             // login (1.5 s), then rates start loading
  await shot(p, '02-rates-loading');
  await p.waitForTimeout(2000);
  await shot(p, '03-rates-success');

  mark('2 open wallet before order');
  await tap(309, 800, 300); await shot(p, '04-wallet-loading');
  await p.waitForTimeout(1800); await shot(p, '05-wallet-before');
  await tap(103, 800, 2500);

  mark('3 buy 100 EUR');
  await tap(200, 268, 1000); await shot(p, '06-order-form');
  await tap(200, 288, 500); await shot(p, '07-order-sending');
  await p.waitForTimeout(1800); await shot(p, '08-order-confirmed');

  mark('4 wallet after order');
  await tap(28, 27, 800);  await tap(309, 800, 2500); await shot(p, '09-wallet-after');
  await tap(103, 800, 2500);

  mark('5 validation: amount 0.001 (server says INVALID_AMOUNT)');
  p.delayMs = 0;
  await tap(200, 268, 1000); await setAmount('0.001');
  await tap(200, 288, 1500); await shot(p, '10-order-validation');

  mark('6 network off: buy 50 EUR');
  await setAmount('50'); await ctx.setOffline(true);
  await tap(200, 288, 6000); await shot(p, '11-order-no-connection');
  await ctx.setOffline(false);
  mark('7 network back: check order status');
  await tap(299, 533, 2000); await shot(p, '12-order-not-executed');

  mark('8 send the same order again (same requestId)');
  await tap(200, 288, 2000); await shot(p, '13-order-confirmed-after-retry');

  mark('9 NBP publishes a new EUR rate; user still sees the old one');
  await tap(28, 27, 800);
  execSync(`cd ${BACKEND} && python seed.py --set-rate EUR 4.2710 >> ${LOG}`);
  await tap(200, 268, 1000); await setAmount('10');
  await tap(200, 288, 2000); await shot(p, '14-order-rate-changed');
  await tap(28, 27, 800);

  mark('10 network off: refresh rates');
  await ctx.setOffline(true);
  await tap(388, 27, 300); await shot(p, '15-rates-loading-offline');
  await p.waitForTimeout(5000); await shot(p, '16-rates-no-connection');
  await ctx.setOffline(false);
  mark('11 network back: refresh rates');
  await tap(388, 27, 2000); await shot(p, '17-rates-refreshed');

  mark('12 buy 900 EUR (more than the PLN balance)');
  await tap(200, 268, 1000); await setAmount('900');
  await tap(200, 288, 2000); await shot(p, '18-order-insufficient-funds');
  await tap(28, 27, 800);

  mark('13 final wallet');
  await tap(309, 800, 2500); await shot(p, '19-wallet-final');
  await b.close();
})();
