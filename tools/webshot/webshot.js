// Screenshot harness for the web build. Serves build/web on 127.0.0.1:8123, loads it in headless
// Chromium with SwiftShader, waits, clicks once (mouse capture / audio), screenshots.
//   cd tools/webshot && npm install
//   QS='?spawn=8,30,0,-12&showroom&hour=11' SHOT=shot.png WAIT=45000 node webshot.js
// Env: QS query string (spawn=x,z,yaw,pitch[,y], hour=H, showroom), SHOT output file, WAIT ms.
// It deliberately presses no keys: the build runs at ~1 FPS here and a 1 ms tap moves the
// player meters. Set CHROME to the Chromium binary if it is not at the default path.
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const path0 = require('path');
const root = path0.resolve(__dirname, '..', '..', 'build', 'web');
const types = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png'};
const server = http.createServer((req,res)=>{ const f = path.join(root, req.url.split('?')[0]==='/'?'index.html':req.url.split('?')[0]); fs.readFile(f,(e,d)=>{ if(e){res.writeHead(404);res.end();return;} res.writeHead(200,{'Content-Type':types[path.extname(f)]||'application/octet-stream'}); res.end(d); }); });
(async () => {
  await new Promise(r=>server.listen(8123,r));
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist','--enable-webgl','--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const logs = [];
  page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
  await page.goto('http://127.0.0.1:8123/index.html' + (process.env.QS || ''));
  await page.waitForTimeout(parseInt(process.env.WAIT || '25000'));
  await page.mouse.click(480, 270);

  await page.waitForTimeout(1500);

  await page.waitForTimeout(3000);
  await page.screenshot({ path: process.env.SHOT || 'web_shot2.png' });
  console.log(logs.filter(l => /error|Error|pageerror|warn|shader|Shader/i.test(l)).slice(0, 20).join('\n') || 'no errors/warnings');
  await browser.close(); server.close();
})().catch(e => { console.error('TEST FAILED', e); process.exit(1); });
