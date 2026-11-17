const { chromium, devices } = require('playwright');
exports.start = async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ ...devices['Pixel 7'] });
  const p = await ctx.newPage();
  // Optional extra latency on calls to the service so the loading state is visible.
  p.delayMs = 0;
  await p.route('http://127.0.0.1:8000/**', async r => { if (p.delayMs) await new Promise(x => setTimeout(x, p.delayMs)); await r.continue(); });
  await p.goto(process.env.APP_URL || 'http://127.0.0.1:8080/');
  await p.waitForTimeout(5000);
  return { b, ctx, p };
};
const SHOTS = process.env.SHOTS || 'shots';
exports.shot = (p, name) => p.screenshot({ path: `${SHOTS}/${name}.png` });
