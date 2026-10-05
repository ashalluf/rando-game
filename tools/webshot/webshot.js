// Screenshot harness for the web build. Serves build/web on 127.0.0.1:8123, loads it in headless
// Chromium with SwiftShader, waits, clicks once (mouse capture / audio), screenshots.
//   cd tools/webshot && npm install
//   QS='?spawn=8,30,0,-12&showroom&hour=11' SHOT=shot.png WAIT=45000 node webshot.js
// Env: QS query string (spawn=x,z,yaw,pitch[,y], hour=H, showroom), SHOT output file, WAIT ms,
// LOG file for the whole timestamped console and the JS heap at the end, FPS_SECONDS to count
// frames before the shot, WEB_ROOT another export folder (e.g. a before build).
// It deliberately presses no keys: the build runs at ~1 FPS here and a 1 ms tap moves the
// player meters. Set CHROME to the Chromium binary if it is not at the default path.
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const path0 = require('path');
const PORT = parseInt(process.env.PORT || '8123'); // PORT=... runs two harnesses at once
const root = process.env.WEB_ROOT ? path0.resolve(process.env.WEB_ROOT) : path0.resolve(__dirname, '..', '..', 'build', 'web');
const types = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png'};
const server = http.createServer((req,res)=>{ const f = path.join(root, req.url.split('?')[0]==='/'?'index.html':req.url.split('?')[0]); fs.readFile(f,(e,d)=>{ if(e){res.writeHead(404);res.end();return;} res.writeHead(200,{'Content-Type':types[path.extname(f)]||'application/octet-stream'}); res.end(d); }); });
(async () => {
  await new Promise(r=>server.listen(PORT,r));
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist','--enable-webgl','--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: parseInt(process.env.VW || '960'), height: parseInt(process.env.VH || '540') } });
  const logs = [];
  const t0 = Date.now(); const stamp = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
  const note = l => { logs.push(l); if (process.env.LOG) fs.appendFileSync(process.env.LOG, l + '\n'); };
  if (process.env.LOG) fs.writeFileSync(process.env.LOG, '');
  page.on('console', m => note(`${stamp()} [${m.type()}] ${m.text()}`));
  page.on('pageerror', e => note(`${stamp()} [pageerror] ${e.message}`));
  await page.goto(`http://127.0.0.1:${PORT}/index.html` + (process.env.QS || ''));
  await page.waitForTimeout(parseInt(process.env.WAIT || '25000'));
  await page.mouse.click(parseInt(process.env.VW || '960') / 2, parseInt(process.env.VH || '540') / 2);

  await page.waitForTimeout(1500);

  await page.waitForTimeout(3000);
  if (process.env.FPS_SECONDS) {
    // Browser frames (one Godot frame each) counted over FPS_SECONDS with no input: the web
    // build's frame time on this machine, to compare two builds on the same view.
    const secs = parseFloat(process.env.FPS_SECONDS);
    const r = await page.evaluate(s => new Promise(done => { let n = 0; const t0 = performance.now();
      const tick = () => { n++; if (performance.now() - t0 < s * 1000) requestAnimationFrame(tick); else done({frames: n, ms: performance.now() - t0}); };
      requestAnimationFrame(tick); }), secs);
    note(`${stamp()} [fps] ${r.frames} frames in ${(r.ms / 1000).toFixed(1)} s = ${(r.ms / r.frames).toFixed(0)} ms a frame`);
  }
  await page.screenshot({ path: process.env.SHOT || 'web_shot2.png', timeout: parseInt(process.env.SHOT_TIMEOUT || '180000') });
  if (process.env.LOG) {
    // The whole console, timestamped from page load, plus the JS heap at the end (LOG=file).
    const mem = await page.evaluate(() => performance.memory ? JSON.stringify({used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize}) : 'n/a').catch(() => 'n/a');
    fs.appendFileSync(process.env.LOG, `${stamp()} [heap] ${mem}\n`);
  }
  console.log(logs.filter(l => /error|Error|pageerror|warn|shader|Shader/i.test(l)).slice(0, 20).join('\n') || 'no errors/warnings');
  await browser.close(); server.close();
})().catch(e => { console.error('TEST FAILED', e); process.exit(1); });
