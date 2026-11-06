// GLPROBE=1 on webshot.js (web-bonfire): logs every instanced draw of one frame (GLPROBE_FRAME,
// default 15) with the bound vertex array, index buffer and the state of every enabled vertex
// attribute (buffer, size, type, stride, offset, divisor) - to tell a draw the browser gets wrong
// from one it gets right.
(() => {
const G = window.WebGL2RenderingContext;
if (!G) return;
let frame = 0;
setInterval(() => console.log('[gl] frames ' + frame), 5000);
const want = parseInt(new URLSearchParams(location.search).get('glframe') || '15');
const raf = window.requestAnimationFrame;
window.requestAnimationFrame = function (cb) { return raf.call(window, function (t) { frame++; return cb(t); }); };
let nid = 1;
const ids = new WeakMap();
const id = o => { if (!o) return 0; if (!ids.has(o)) ids.set(o, nid++); return ids.get(o); };
const bufSize = new WeakMap();
for (const f of ['createBuffer', 'createVertexArray', 'createTexture']) {
  const o = G.prototype[f];
  G.prototype[f] = function () { const r = o.apply(this, arguments); id(r); return r; };
}
const bd = G.prototype.bufferData;
G.prototype.bufferData = function (target, data) {
  const b = this.getParameter(target === this.ARRAY_BUFFER ? this.ARRAY_BUFFER_BINDING : this.ELEMENT_ARRAY_BUFFER_BINDING);
  if (b) bufSize.set(b, typeof data === 'number' ? data : (data ? data.byteLength : 0));
  return bd.apply(this, arguments);
};
const bsd = G.prototype.bufferSubData;
function dump(gl, what, mode, count, type, offset, inst) {
  if (frame % want !== 0) return;
  const vao = gl.getParameter(gl.VERTEX_ARRAY_BINDING);
  const eb = gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING);
  const prog = gl.getParameter(gl.CURRENT_PROGRAM);
  const parts = [];
  for (let i = 0; i < 16; i++) {
    if (!gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_ENABLED)) continue;
    const b = gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);
    parts.push(`a${i}:b${id(b)}(${bufSize.get(b)}) s${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_SIZE)} t${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_TYPE)} st${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_STRIDE)} o${gl.getVertexAttribOffset(i, gl.VERTEX_ATTRIB_ARRAY_POINTER)} d${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_DIVISOR)} n${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_NORMALIZED) ? 1 : 0} i${gl.getVertexAttrib(i, gl.VERTEX_ATTRIB_ARRAY_INTEGER) ? 1 : 0}`);
  }
  let pos = '';
  if (inst > 0) {
    const b0 = gl.getVertexAttrib(0, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);
    const prevAB = gl.getParameter(gl.ARRAY_BUFFER_BINDING);
    if (b0) {
      gl.bindBuffer(gl.ARRAY_BUFFER, b0);
      const f = new Float32Array(16);
      try { gl.getBufferSubData(gl.ARRAY_BUFFER, 0, f); pos = ' pos[' + Array.from(f.slice(0, 12)).map(v => v.toFixed(2)).join(',') + ']'; } catch (e) { pos = ' pos?' + e.message; }
      const b12 = gl.getVertexAttrib(12, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);
      if (b12) {
        gl.bindBuffer(gl.ARRAY_BUFFER, b12);
        const g = new Float32Array(16 * inst);
        try { gl.getBufferSubData(gl.ARRAY_BUFFER, 0, g); pos += ' inst0[' + Array.from(g.slice(0, 12)).map(v => v.toFixed(2)).join(',') + ']';
          const ys = []; for (let k = 0; k < inst; k++) ys.push(g[k * 16 + 7].toFixed(2) + '/' + g[k * 16].toFixed(2)); pos += ' ys[' + ys.join(' ') + ']'; } catch (e) {}
      }
      gl.bindBuffer(gl.ARRAY_BUFFER, prevAB);
    }
    const b4 = gl.getVertexAttrib(4, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);
    if (b4) {
      const pab = gl.getParameter(gl.ARRAY_BUFFER_BINDING);
      gl.bindBuffer(gl.ARRAY_BUFFER, b4);
      const f = new Float32Array(8);
      try { gl.getBufferSubData(gl.ARRAY_BUFFER, gl.getVertexAttribOffset(4, gl.VERTEX_ATTRIB_ARRAY_POINTER), f); pos += ' uv[' + Array.from(f).map(v => v.toFixed(2)).join(',') + ']'; } catch (e) { pos += ' uv?' + e.message; }
      gl.bindBuffer(gl.ARRAY_BUFFER, pab);
    }
    const b15 = gl.getVertexAttrib(15, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);
    if (b15) {
      const pab = gl.getParameter(gl.ARRAY_BUFFER_BINDING);
      gl.bindBuffer(gl.ARRAY_BUFFER, b15);
      const u = new Uint16Array(32);
      try { gl.getBufferSubData(gl.ARRAY_BUFFER, 48, u); pos += ' cc0[' + Array.from(u.slice(0, 8)).join(',') + ']'; } catch (e) {}
      gl.bindBuffer(gl.ARRAY_BUFFER, pab);
    }
    const tex = gl.getParameter(gl.TEXTURE_BINDING_2D);
    pos += ' tex' + id(tex) + ' unit' + gl.getParameter(gl.ACTIVE_TEXTURE);
    const pg = gl.getParameter(gl.CURRENT_PROGRAM);
    for (const un of ['compressed_aabb_size', 'compressed_aabb_position', 'uv_scale', 'model_flags']) {
      const loc = gl.getUniformLocation(pg, un);
      if (loc) { const v = gl.getUniform(pg, loc); pos += ` ${un}=` + (v && v.length ? Array.from(v).map(x => (+x).toFixed(3)).join(',') : v); }
    }
    const wl = gl.getUniformLocation(pg, 'world_transform');
    if (wl) { const v = gl.getUniform(pg, wl); pos += ' wt=' + Array.from(v).map(x => (+x).toFixed(2)).join(','); }
    const ib = gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING);
    if (ib) { const u = new Uint16Array(6); try { gl.getBufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, u); pos += ' idx[' + Array.from(u).join(',') + ']'; } catch (e) {} }
  }
  console.log(`[gl] f${frame}${pos} ${what} mode${mode} n${count} type${type} off${offset} inst${inst} vao${id(vao)} eb${id(eb)}(${bufSize.get(eb)}) prog${id(prog)} ${parts.join(' ')}`);
}
let told = false;
const dei = G.prototype.drawElementsInstanced;
const tell = gl => { if (told) return; told = true; const e = gl.getExtension('WEBGL_debug_renderer_info'); console.log('[gl] renderer ' + (e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER))); };
G.prototype.drawElementsInstanced = function (mode, count, type, offset, inst) { tell(this); brief(this, 'DEI', count, inst); dump(this, 'DEI', mode, count, type, offset, inst); return dei.apply(this, arguments); };
const dai = G.prototype.drawArraysInstanced;
G.prototype.drawArraysInstanced = function (mode, first, count, inst) { dump(this, 'DAI', mode, count, 0, first, inst); return dai.apply(this, arguments); };
function brief(gl, what, count, inst) {
  if (frame % want !== 0) return;
  const vao = gl.getParameter(gl.VERTEX_ARRAY_BINDING);
  const fb = gl.getParameter(gl.FRAMEBUFFER_BINDING);
  console.log(`[glb] f${frame} ${what} n${count} inst${inst} vao${id(vao)} fb${id(fb)} prog${id(gl.getParameter(gl.CURRENT_PROGRAM))} dmask${gl.getParameter(gl.DEPTH_WRITEMASK) ? 1 : 0} dtest${gl.isEnabled(gl.DEPTH_TEST) ? 1 : 0} blend${gl.isEnabled(gl.BLEND) ? 1 : 0} cmask${gl.getParameter(gl.COLOR_WRITEMASK).map(x => x ? 1 : 0).join('')} dfunc${gl.getParameter(gl.DEPTH_FUNC)} drange${Array.from(gl.getParameter(gl.DEPTH_RANGE)).join(',')} poff${gl.isEnabled(gl.POLYGON_OFFSET_FILL) ? 1 : 0}:${gl.getParameter(gl.POLYGON_OFFSET_FACTOR)},${gl.getParameter(gl.POLYGON_OFFSET_UNITS)} cull${gl.isEnabled(gl.CULL_FACE) ? gl.getParameter(gl.CULL_FACE_MODE) : 0} bf${gl.getParameter(gl.BLEND_SRC_RGB)},${gl.getParameter(gl.BLEND_DST_RGB)},${gl.getParameter(gl.BLEND_SRC_ALPHA)},${gl.getParameter(gl.BLEND_DST_ALPHA)} sc${gl.isEnabled(gl.SCISSOR_TEST) ? 1 : 0}`);
}
const de = G.prototype.drawElements;
G.prototype.drawElements = function (mode, count, type, offset) { brief(this, 'DE', count, 0); return de.apply(this, arguments); };
const da = G.prototype.drawArrays;
G.prototype.drawArrays = function (mode, first, count) { brief(this, 'DA', count, 0); return da.apply(this, arguments); };
const cf = G.prototype.createFramebuffer;
G.prototype.createFramebuffer = function () { const r = cf.apply(this, arguments); id(r); return r; };
const cp = G.prototype.createProgram;
G.prototype.createProgram = function () { const r = cp.apply(this, arguments); id(r); return r; };
})();
