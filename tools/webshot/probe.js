// PROBE=1 on webshot.js loads this into the page before Godot: tallies what the page allocates
// outside the wasm heap - Web Audio buffers (Godot's sample playback decodes a whole stream into
// one on its first play), buffer sources, AudioWorklet nodes, WebGL uploads - and prints a
// [probe] line every 10 s while anything changes.
(() => {
const t = {bufs: 0, bufMB: 0, worklets: 0, sources: 0, glMB: 0, big: []};
const AC = window.AudioContext || window.webkitAudioContext;
if (AC) {
  const cb = AC.prototype.createBuffer;
  AC.prototype.createBuffer = function (ch, len, rate) {
    t.bufs++; const mb = ch * len * 4 / 1e6; t.bufMB += mb;
    if (mb > 2) {
          // The JS callers (Godot's sample code), wasm frames dropped: which path duplicated it.
          const st = (new Error().stack || '').split('\n').slice(2).map(l => l.trim().split(' ')[1]).filter(f => f && !/^(wasm|<anon|\$|null)/.test(f) && !f.includes('.wasm')).slice(0, 4).join('<');
          t.big.push(`${mb.toFixed(1)}MB/${(len / rate).toFixed(1)}s[${st}]`);
        }
    return cb.apply(this, arguments);
  };
  const cs = AC.prototype.createBufferSource;
  AC.prototype.createBufferSource = function () { t.sources++; return cs.apply(this, arguments); };
}
if (window.AudioWorkletNode) {
  const W = window.AudioWorkletNode;
  window.AudioWorkletNode = function () { t.worklets++; return Reflect.construct(W, arguments, new.target || W); };
  window.AudioWorkletNode.prototype = W.prototype;
}
const G = window.WebGL2RenderingContext;
if (G) for (const f of ['bufferData', 'texImage2D', 'texImage3D', 'compressedTexImage2D', 'compressedTexImage3D', 'texStorage2D', 'texStorage3D']) {
  const o = G.prototype[f];
  G.prototype[f] = function () {
    for (const a of arguments) if (a && a.byteLength) { t.glMB += a.byteLength / 1e6; break; }
    return o.apply(this, arguments);
  };
}
// The wasm heap (Godot's whole memory: a browser caps it at 4 GB).
let mem = null;
const grab = r => { const i = r && (r.instance || r); if (i && i.exports) for (const k in i.exports) if (i.exports[k] instanceof WebAssembly.Memory) mem = i.exports[k]; return r; };
const ins = WebAssembly.instantiate, insS = WebAssembly.instantiateStreaming;
WebAssembly.instantiate = function () { return ins.apply(this, arguments).then(grab); };
if (insS) WebAssembly.instantiateStreaming = function () { return insS.apply(this, arguments).then(grab); };
let last = '';
setInterval(() => {
  const l = `[probe] wasm ${mem ? (mem.buffer.byteLength / 1e6).toFixed(0) : '?'} MB, audio buffers ${t.bufs} (${t.bufMB.toFixed(0)} MB) sources ${t.sources} worklets ${t.worklets} gl uploads ${t.glMB.toFixed(0)} MB` + (t.big.length ? ' big: ' + t.big.splice(0).join(' ') : '');
  if (l !== last) { console.log(l); last = l; }
}, 10000);
})();
