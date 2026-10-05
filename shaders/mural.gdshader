shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Murals, ghost signs, painted crosswalks and painted utility cabinets (scripts/world/murals.gd).
// One material for all of it, so a chunk's paint is ONE MultiMesh draw ("mural"). Transparent,
// drawn before the street wear (render_priority -1 on the material), so a tag sprayed over a
// mural lies on top of it.
//
// Every picture is painted HERE from a seed - nothing is an artist's work, there is no lettering
// but the ghost signs' invented names, and there are no faces: landscapes (a sunset coast with
// palms, layered mountains over a poppy field, a desert of mesas and saguaros), a botanical field
// of big leaves and flowers, bands of folk-art geometry (zigzags, stepped frets, diamonds,
// sawteeth, rosettes) and scalloped waves. Painted the way a wall is painted: flat colour areas
// with hand-cut, wobbling edges, brush strokes in each area, a dark outline round the shapes, the
// wall's own grain through the paint (read off the screen like the street wear), sun fade and
// flaking.
//
// * The mesh is a unit quad (x -0.5..0.5, y -0.5..0.5, facing +Z); the instance basis is
//   (right * w, up * h, normal * w), so a piece's size in metres is the basis' column lengths.
// * INSTANCE_CUSTOM: r = mode * 16 + scene, g = seed 0..1, b = this piece's left edge in metres
//   within the whole design (a mural split into panels between pilasters, a crosswalk in strips)
//   or the ghost sign's atlas cell, a = substrate + 8 * wear (0..7). Small integers and 0..1, so
//   they survive Compatibility's half-float instance data.
// * Instance COLOR: modes 0, 2, 3, 4: r = the whole design's width (metres), g = age (0 fresh,
//   1 old). Mode 1 (ghost sign): rgb = the wall's colour (sRGB, for the patch painted over part of
//   it), a = age. Instance colours arrive raw on both renderers.
// * Modes: 0 a mural (scene 0-5), 1 a ghost sign, 2 a painted crosswalk (scene = pattern),
//   3 a painted cabinet face (scene 0-5, small), 4 a frieze (a folk band along a wall).
// * Colour: the palettes are sRGB, taken to linear and handed back with cs_out()
//   (color_space.gdshaderinc), so both renderers draw the same albedo.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D ghost_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform bool use_screen = true;
uniform float depth_pull = 0.002;
// Distance (m) the batch stops drawing at (Murals.DRAW_DISTANCE): the paint thins out over the
// last fifth of it, so nothing pops when the batch's own visibility range ends.
uniform float fade_end = 230.0;

// Eight palettes of eight: sky top, sky middle, sky low, sun, accent 1, accent 2, dark, light.
const vec3 PAL[64] = vec3[64](
	// 0 sunset
	vec3(0.23, 0.16, 0.42), vec3(0.78, 0.27, 0.45), vec3(0.98, 0.55, 0.25), vec3(1.0, 0.83, 0.35),
	vec3(0.07, 0.38, 0.45), vec3(0.95, 0.75, 0.55), vec3(0.12, 0.08, 0.15), vec3(0.98, 0.93, 0.80),
	// 1 dawn pastel
	vec3(0.45, 0.62, 0.82), vec3(0.93, 0.70, 0.72), vec3(0.99, 0.85, 0.62), vec3(1.0, 0.95, 0.80),
	vec3(0.35, 0.55, 0.55), vec3(0.83, 0.72, 0.55), vec3(0.20, 0.22, 0.30), vec3(0.97, 0.96, 0.90),
	// 2 desert noon
	vec3(0.18, 0.55, 0.70), vec3(0.45, 0.75, 0.80), vec3(0.95, 0.85, 0.65), vec3(1.0, 0.92, 0.55),
	vec3(0.78, 0.38, 0.22), vec3(0.90, 0.62, 0.38), vec3(0.20, 0.30, 0.18), vec3(0.98, 0.95, 0.86),
	// 3 folk brights
	vec3(0.85, 0.15, 0.35), vec3(0.98, 0.60, 0.10), vec3(0.98, 0.85, 0.20), vec3(0.15, 0.55, 0.75),
	vec3(0.10, 0.60, 0.40), vec3(0.55, 0.20, 0.60), vec3(0.10, 0.10, 0.15), vec3(0.97, 0.95, 0.88),
	// 4 night
	vec3(0.06, 0.08, 0.22), vec3(0.18, 0.20, 0.45), vec3(0.55, 0.35, 0.55), vec3(0.98, 0.92, 0.75),
	vec3(0.12, 0.35, 0.42), vec3(0.85, 0.55, 0.35), vec3(0.04, 0.04, 0.08), vec3(0.90, 0.90, 0.95),
	// 5 earth
	vec3(0.55, 0.25, 0.18), vec3(0.85, 0.55, 0.30), vec3(0.95, 0.80, 0.55), vec3(0.98, 0.88, 0.60),
	vec3(0.25, 0.40, 0.30), vec3(0.60, 0.50, 0.30), vec3(0.18, 0.12, 0.10), vec3(0.95, 0.90, 0.80),
	// 6 ocean
	vec3(0.10, 0.30, 0.50), vec3(0.25, 0.60, 0.75), vec3(0.70, 0.88, 0.90), vec3(1.0, 0.90, 0.60),
	vec3(0.05, 0.45, 0.50), vec3(0.95, 0.80, 0.60), vec3(0.05, 0.12, 0.20), vec3(0.96, 0.97, 0.95),
	// 7 jacaranda
	vec3(0.38, 0.30, 0.62), vec3(0.60, 0.50, 0.80), vec3(0.85, 0.75, 0.90), vec3(0.99, 0.85, 0.50),
	vec3(0.25, 0.50, 0.35), vec3(0.90, 0.55, 0.60), vec3(0.12, 0.10, 0.20), vec3(0.97, 0.95, 0.97));

// Ghost-sign paints (sRGB): the field, the lettering, the shadow and second line.
const vec3 GHOST_FIELD[6] = vec3[6](vec3(0.36, 0.10, 0.08), vec3(0.08, 0.08, 0.08), vec3(0.12, 0.24, 0.16),
	vec3(0.10, 0.14, 0.28), vec3(0.62, 0.45, 0.14), vec3(0.85, 0.82, 0.72));
const vec3 GHOST_INK[4] = vec3[4](vec3(0.93, 0.90, 0.80), vec3(0.96, 0.96, 0.94), vec3(0.95, 0.80, 0.30), vec3(0.12, 0.10, 0.09));
const vec3 GHOST_SECOND[4] = vec3[4](vec3(0.62, 0.12, 0.10), vec3(0.10, 0.10, 0.10), vec3(0.88, 0.84, 0.72), vec3(0.20, 0.32, 0.55));

varying flat vec4 v_col;
varying flat vec4 v_custom;
varying flat vec2 v_size;

float mh(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float mh1(float x) {
	return mh(vec2(x, x * 0.37 + 11.7));
}

float mnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mh(i), mh(i + vec2(1.0, 0.0)), f.x), mix(mh(i + vec2(0.0, 1.0)), mh(i + vec2(1.0, 1.0)), f.x), f.y);
}

float mfbm(vec2 p) {
	return mnoise(p) * 0.55 + mnoise(p * 2.13 + 7.1) * 0.3 + mnoise(p * 4.7 + 3.3) * 0.15;
}

vec3 pal(int palette, int i) {
	return cs_srgb_to_linear(PAL[palette * 8 + i]);
}

vec3 lin(vec3 srgb) {
	return cs_srgb_to_linear(srgb);
}

// A shape's coverage from its signed distance (negative inside), softened by the pixel and by
// the brush (`soft`, metres).
float fill(float d, float px) {
	return 1.0 - smoothstep(-px, px, d);
}

// Paint `c` over `col` where the shape is, with a dark outline `line` metres wide round it.
vec3 layer(vec3 col, vec3 c, float d, float px, float line, vec3 ink) {
	if (line > 0.0) {
		col = mix(col, ink, fill(d - line, px));
	}
	return mix(col, c, fill(d, px));
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// --- Pieces of scenery (all in metres; H the design's height) ------------------------------------

// A palm: trunk from `base`, `h` tall, its top `lean` metres over, a crown of drooping feathered
// fronds. Signed distance (negative inside).
float palm(vec2 p, vec2 base, float h, float lean, float s) {
	float t = (p.y - base.y) / h;
	float cx = base.x + lean * t * t;
	float hw = h * (0.024 - 0.010 * clamp(t, 0.0, 1.0));
	float d = max(abs(p.x - cx) - hw, max(-t, t - 1.0) * h);
	vec2 c = base + vec2(lean, h);
	float L = h * 0.34;
	if (length(p - c) > L * 1.25) {
		return d;
	}
	for (int k = 0; k < 9; k++) {
		float fk = float(k);
		float a = 3.14159 * (0.02 + 0.96 * fk / 8.0) + (mh1(s + fk) - 0.5) * 0.3;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 n = vec2(-dir.y, dir.x);
		vec2 v = p - c;
		float x = dot(v, dir);
		float y = dot(v, n);
		float len = L * (0.75 + 0.35 * mh1(s * 3.1 + fk));
		if (x < 0.0 || x > len) {
			continue;
		}
		float droop = (0.55 + 0.3 * mh1(s + fk * 7.0)) * x * x / len;
		float cy = -cos(a) * droop - abs(sin(a)) * 0.0;
		float u = x / len;
		// Leaflets: the blade's edge notched along its length.
		float w = len * 0.11 * pow(sin(3.14159 * min(u * 1.15, 1.0)), 0.6) * (0.45 + 0.55 * abs(sin(u * 28.0 + fk)));
		d = min(d, abs(y - cy) - w);
	}
	// Coconuts under the crown.
	d = min(d, length(p - c + vec2(0.0, h * 0.025)) - h * 0.03);
	return d;
}

// A saguaro: a trunk and up to two arms that turn up.
float saguaro(vec2 p, vec2 base, float h, float s) {
	float r = h * 0.075;
	float d = sd_seg(p, base, base + vec2(0.0, h - r), r);
	for (int k = 0; k < 2; k++) {
		float side = k == 0 ? -1.0 : 1.0;
		if (mh1(s + float(k) * 3.7) < 0.25) {
			continue;
		}
		float y0 = h * (0.3 + 0.25 * mh1(s * 1.7 + float(k)));
		float out_ = h * (0.16 + 0.06 * mh1(s * 2.3 + float(k)));
		float up = h * (0.18 + 0.2 * mh1(s * 3.9 + float(k)));
		vec2 a = base + vec2(0.0, y0);
		vec2 b = a + vec2(side * out_, 0.0);
		d = min(d, sd_seg(p, a, b, r * 0.8));
		d = min(d, sd_seg(p, b, b + vec2(0.0, up), r * 0.8));
	}
	return d;
}

// A sky in posterised bands with wavy edges, from `low` at the horizon to `top`.
vec3 banded_sky(vec2 p, float horizon, float H, int P, float s) {
	float t = clamp((p.y - horizon) / max(H - horizon, 0.01), 0.0, 1.0);
	float wav = 0.035 * sin(p.x / H * 3.0 + s) + 0.02 * (mnoise(vec2(p.x / H * 6.0, s)) - 0.5);
	float band = floor((t + wav) * 5.0) / 4.0;
	band = clamp(band, 0.0, 1.0);
	vec3 low = pal(P, 2);
	vec3 mid = pal(P, 1);
	vec3 top = pal(P, 0);
	return band < 0.5 ? mix(low, mid, band * 2.0) : mix(mid, top, band * 2.0 - 1.0);
}

// Birds far off: little Vs.
float birds(vec2 p, vec2 at, float H, float s) {
	float d = 1e3;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		vec2 c = at + vec2((mh1(s + fk) - 0.5) * H * 0.9, (mh1(s * 2.0 + fk) - 0.5) * H * 0.18);
		float w = H * (0.022 + 0.012 * mh1(s * 5.0 + fk));
		vec2 q = p - c;
		q.x = abs(q.x);
		d = min(d, sd_seg(q, vec2(0.0), vec2(w, w * 0.45), H * 0.004));
	}
	return d;
}

// --- Scenes -----------------------------------------------------------------------------------
// Each takes the point and the design's size (metres), the seed and the pixel size, and returns
// the paint colour (linear).

vec3 scene_coast(vec2 p, vec2 S, float s, float px) {
	float H = S.y;
	int P = int(mh1(s) * 3.0) == 0 ? 0 : (int(mh1(s) * 3.0) == 1 ? 4 : 6);
	float horizon = H * (0.3 + 0.08 * mh1(s + 1.0));
	vec3 col = banded_sky(p, horizon, H, P, s);
	// The sun on the horizon, cut by stripes in its lower half.
	float sx = S.x * (0.25 + 0.5 * mh1(s + 2.0));
	float R = H * (0.2 + 0.08 * mh1(s + 3.0));
	vec2 sp = p - vec2(sx, horizon);
	float sun = length(sp) - R;
	float yy = sp.y / R;
	float cut = yy < 0.55 ? step(fract(yy * 6.0), 0.18 + 0.4 * (0.55 - yy)) : 0.0;
	col = mix(col, mix(pal(P, 3), pal(P, 2), 0.2 * (1.0 - yy)), fill(sun, px) * (1.0 - cut));
	col = mix(col, pal(P, 7), fill(birds(p, vec2(S.x * 0.6, H * 0.8), H, s), px) * 0.0);
	col = mix(col, pal(P, 6), fill(birds(p, vec2(S.x * mh1(s + 9.0), H * 0.78), H, s), px));
	if (p.y < horizon) {
		// The sea: bands deepening toward the shore, lit dashes, the sun's road.
		float t = (horizon - p.y) / horizon;
		vec3 sea = mix(pal(P, 4), pal(P, 6), floor(t * 3.0) / 3.0 * 0.6);
		vec2 dc = vec2(p.x / (H * 0.12), p.y / (H * 0.03));
		vec2 id = floor(dc + vec2(mh1(floor(dc.y)) * 3.0, 0.0));
		vec2 f = fract(dc + vec2(mh1(floor(dc.y)) * 3.0, 0.0));
		float dash = step(0.55, mh(id + s)) * step(abs(f.y - 0.5), 0.18) * step(abs(f.x - 0.5), 0.35);
		float road = 1.0 - smoothstep(R * 0.2, R * (0.9 - 0.5 * t), abs(p.x - sx));
		vec3 glint = mix(pal(P, 7), pal(P, 3), road);
		sea = mix(sea, glint, dash * (0.35 + 0.65 * road));
		col = sea;
		// The beach.
		float shore = H * (0.08 + 0.03 * sin(p.x / H * 2.0 + s)) + 0.01 * H * (mnoise(vec2(p.x * 3.0 / H, s)) - 0.5);
		col = mix(col, pal(P, 7), fill(abs(p.y - shore - H * 0.012) - H * 0.006, px));
		col = mix(col, pal(P, 5), fill(p.y - shore, px));
	}
	// Palms, one per slot, in silhouette.
	float slot = H * 0.62;
	float i0 = floor(p.x / slot);
	float d = 1e3;
	for (int k = -1; k <= 1; k++) {
		float i = i0 + float(k);
		float ps = s * 13.0 + i * 7.3;
		if (mh1(ps) < 0.3 || abs((i + 0.5) * slot - sx) < R * 0.8) {
			continue;
		}
		float h = H * (0.55 + 0.38 * mh1(ps + 1.0));
		vec2 base = vec2((i + 0.2 + 0.6 * mh1(ps + 2.0)) * slot, H * 0.04);
		float lean = (mh1(ps + 3.0) - 0.5) * H * 0.35;
		d = min(d, palm(p, base, h, lean, ps));
	}
	col = mix(col, pal(P, 6), fill(d, px));
	return col;
}

vec3 scene_mountains(vec2 p, vec2 S, float s, float px) {
	float H = S.y;
	int P = int(mh1(s) * 3.0) == 0 ? 1 : (int(mh1(s) * 3.0) == 1 ? 5 : 7);
	float horizon = H * 0.45;
	vec3 col = banded_sky(p, horizon, H, P, s + 4.0);
	// A sun or a moon behind the range, and a cloud or two.
	vec2 sc = vec2(S.x * (0.2 + 0.6 * mh1(s + 5.0)), H * (0.72 + 0.1 * mh1(s + 6.0)));
	col = mix(col, pal(P, 3), fill(length(p - sc) - H * 0.1, px));
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		vec2 cc = vec2(S.x * mh1(s * 3.0 + fk), H * (0.8 + 0.12 * mh1(s * 5.0 + fk)));
		vec2 q = (p - cc) / vec2(H * 0.22, H * 0.05);
		float cl = length(q) - 1.0 + 0.25 * sin(q.x * 3.0 + fk);
		col = mix(col, pal(P, 7), fill(cl * H * 0.05, px));
	}
	// Three ridges of peaks, the far ones paler and bluer (the air between), each lit on one
	// flank.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float base = H * (0.5 - 0.12 * fk);
		float amp = H * (0.36 - 0.08 * fk);
		float fx = p.x / H * (1.1 + 0.6 * fk) + s * 3.7 + fk * 13.0;
		float r1 = 1.0 - abs(mnoise(vec2(fx, fk * 7.0)) * 2.0 - 1.0);
		float r2 = 1.0 - abs(mnoise(vec2(fx * 2.3, fk * 7.0 + 3.0)) * 2.0 - 1.0);
		float ridge = base + amp * (r1 * r1 * 0.75 + r2 * r2 * 0.3 + 0.08 * mnoise(vec2(fx * 7.0, fk)));
		float d = p.y - ridge;
		vec3 far_c = mix(pal(P, 0), pal(P, 7), 0.25);
		vec3 rc = mix(pal(P, 6), far_c, 0.72 - 0.33 * fk);
		// The lit flank: the ridge line's fall, looked up down a diagonal from the crest, so the
		// light and shade meet along a line running down from each peak.
		float fxs = fx + (ridge - p.y) / H * (1.1 + 0.6 * fk) * 0.8;
		float e = 0.01;
		float rs = 1.0 - abs(mnoise(vec2(fxs, fk * 7.0)) * 2.0 - 1.0);
		float rs2 = 1.0 - abs(mnoise(vec2(fxs + e, fk * 7.0)) * 2.0 - 1.0);
		rc = mix(rc, mix(rc, pal(P, 3), 0.28), step(0.0, rs2 - rs));
		if (k == 0) {
			// Snow on the far crests.
			float snow = step(base + amp * (0.62 + 0.12 * mnoise(vec2(fx * 6.0, s))), p.y);
			rc = mix(rc, pal(P, 7), snow);
		}
		col = mix(col, rc, fill(d, px));
	}
	// The foreground: a hill of grass with poppies.
	float hill = H * (0.17 + 0.05 * sin(p.x / H * 1.7 + s)) + H * 0.03 * (mnoise(vec2(p.x / H * 4.0, s)) - 0.5);
	vec3 grass = mix(pal(P, 4), lin(vec3(0.75, 0.62, 0.25)), 0.35);
	if (p.y < hill + px) {
		vec2 g = p / (H * 0.045);
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5 - (vec2(mh(id + 1.3), mh(id + 7.1)) - 0.5) * 0.5;
		float r = 0.28 * (0.4 + 0.6 * clamp((hill - p.y) / (H * 0.17), 0.0, 1.0));
		float poppy = step(0.45, mh(id + s)) * fill(length(f) - r, px / (H * 0.045));
		vec3 g2 = mix(grass, poppy > 0.5 ? lin(vec3(0.98, 0.5, 0.08)) : grass, poppy);
		g2 = mix(g2, lin(vec3(0.35, 0.18, 0.05)), poppy * fill(length(f) - r * 0.3, px / (H * 0.045)));
		col = mix(col, g2, fill(p.y - hill, px));
	}
	return col;
}

vec3 scene_desert(vec2 p, vec2 S, float s, float px) {
	float H = S.y;
	int P = int(mh1(s) * 2.0) == 0 ? 2 : 0;
	float horizon = H * 0.32;
	vec3 col = banded_sky(p, horizon, H, P, s + 7.0);
	vec2 sc = vec2(S.x * (0.15 + 0.7 * mh1(s + 8.0)), H * 0.62);
	float sr = H * 0.17;
	col = mix(col, pal(P, 3), fill(length(p - sc) - sr, px));
	col = mix(col, mix(pal(P, 3), pal(P, 2), 0.5), fill(abs(length(p - sc) - sr * 1.25) - sr * 0.04, px));
	// Mesas: flat tops with steep sides, two rows.
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float w = H * (1.1 - 0.3 * fk);
		float i = floor(p.x / w);
		float d = 1e3;
		for (int j = -1; j <= 1; j++) {
			float ii = i + float(j);
			float ms = s * 5.0 + ii * 3.3 + fk * 17.0;
			if (mh1(ms) < 0.3) {
				continue;
			}
			float cx = (ii + 0.5) * w + (mh1(ms + 1.0) - 0.5) * w * 0.4;
			float top = horizon + H * (0.12 + 0.2 * mh1(ms + 2.0)) * (1.0 - 0.35 * fk);
			float half_w = w * (0.2 + 0.2 * mh1(ms + 3.0));
			float dx = abs(p.x - cx) - half_w;
			float side = max(dx, 0.0) * 1.8;
			d = min(d, p.y - (top - side));
		}
		col = mix(col, mix(pal(P, 4), pal(P, 5), fk * 0.6 + 0.2 * step(0.0, sin(p.y / H * 40.0))), fill(max(d, horizon - p.y - H), px));
	}
	// The desert floor in bands.
	if (p.y < horizon) {
		float t = (horizon - p.y) / horizon;
		col = mix(pal(P, 5), pal(P, 4), floor(t * 3.0 + 0.2 * sin(p.x / H * 4.0 + s)) / 3.0 * 0.5);
	}
	// Saguaros in the foreground.
	float slot = H * 0.6;
	float i0 = floor(p.x / slot);
	float d = 1e3;
	for (int k = -1; k <= 1; k++) {
		float i = i0 + float(k);
		float cs = s * 11.0 + i * 5.1;
		if (mh1(cs) < 0.4) {
			continue;
		}
		float h = H * (0.3 + 0.35 * mh1(cs + 1.0));
		d = min(d, saguaro(p, vec2((i + 0.25 + 0.5 * mh1(cs + 2.0)) * slot, H * (0.05 + 0.1 * mh1(cs + 4.0))), h, cs));
	}
	col = layer(col, pal(P, 6) * 1.6 + lin(vec3(0.05, 0.12, 0.04)), d, px, H * 0.006, pal(P, 6));
	return col;
}

// A big leaf, its midrib and veins; `d` out is its distance.
vec3 leaf(vec2 q, float len, float wid, vec3 c, vec3 vein, out float d) {
	// q is in the leaf's frame, x along the blade from its stalk.
	float u = q.x / len;
	float half_w = wid * sqrt(max(u * (1.0 - u), 0.0)) * 2.0;
	d = max(abs(q.y) - half_w, -q.x);
	d = max(d, q.x - len);
	float rib = 1.0 - smoothstep(0.0, wid * 0.05, abs(q.y));
	float veins = 1.0 - smoothstep(0.0, wid * 0.05, abs(fract(u * 7.0 - abs(q.y) / len * 2.5) - 0.5) * len / 7.0);
	return mix(c, vein, max(rib, veins * 0.6 * step(abs(q.y), half_w * 0.85)));
}

vec3 scene_botanical(vec2 p, vec2 S, float s, float px) {
	float H = S.y;
	int P = int(mh1(s) * 3.0) == 0 ? 3 : (int(mh1(s) * 3.0) == 1 ? 7 : 5);
	vec3 bg = mix(pal(P, 6), pal(P, 4), 0.3 + 0.3 * mh1(s + 1.0));
	vec3 col = bg;
	vec3 leaf_dark = lin(vec3(0.08, 0.28, 0.17));
	vec3 leaf_mid = lin(vec3(0.16, 0.45, 0.26));
	vec3 leaf_lt = lin(vec3(0.42, 0.62, 0.3));
	// Two layers: a back layer of big dark leaves in silhouette, then the motifs.
	for (int layer_i = 0; layer_i < 2; layer_i++) {
		float fl = float(layer_i);
		float cell = min(H * (0.55 - 0.15 * fl), 2.2 - 0.6 * fl);
		vec2 g = p / cell + fl * 0.37;
		vec2 i0 = floor(g);
		for (int k = 0; k < 4; k++) {
			vec2 id = i0 + vec2(float(k % 2), float(k / 2)) - vec2(step(fract(g.x), 0.5), step(fract(g.y), 0.5));
			vec2 c = (id + 0.5 + (vec2(mh(id + 3.1 + fl), mh(id + 5.7 + fl)) - 0.5) * 0.5 - fl * 0.37) * cell;
			vec2 v = p - c;
			float kind = layer_i == 0 ? 0.0 : mh(id + 9.3);
			float d;
			vec3 m;
			if (kind < 0.5) {
				float a = mh(id + 2.2 + fl) * 6.283;
				vec2 q = vec2(dot(v, vec2(cos(a), sin(a))), dot(v, vec2(-sin(a), cos(a)))) + vec2(cell * 0.42, 0.0);
				vec3 lc = layer_i == 0 ? mix(bg, leaf_dark, 0.65) : mix(leaf_mid, leaf_lt, mh(id + 4.4));
				m = leaf(q, cell * 0.9, cell * (0.2 + 0.1 * mh(id + 1.9)), lc, layer_i == 0 ? lc * 0.8 : leaf_dark, d);
				// A split leaf now and then: slits cut in from the edge.
				if (mh(id + 6.1) < 0.4) {
					float u = q.x / (cell * 0.9);
					float slit = abs(fract(u * 6.0) - 0.5) * cell * 0.9 / 6.0 - cell * 0.012;
					d = max(d, -max(slit, cell * 0.06 - abs(q.y)));
				}
			} else if (kind < 0.82) {
				// A flower: petals round a centre.
				float n = 5.0 + floor(mh(id + 6.6) * 3.0);
				float r = length(v);
				float th = atan(v.y, v.x) + mh(id) * 6.283;
				float R = cell * (0.28 + 0.1 * mh(id + 8.8));
				float edge = R * (0.55 + 0.45 * pow(abs(cos(th * n * 0.5)), 0.7));
				d = r - edge;
				vec3 pc = pal(P, int(mh(id + 7.7) * 3.0));
				m = mix(pc * 0.8, mix(pc, pal(P, 7), 0.3), smoothstep(edge * 0.3, edge, r));
				m = mix(m, pal(P, 3), fill(r - R * 0.22, px));
				m = mix(m, pal(P, 6), fill(abs(r - R * 0.22) - R * 0.03, px));
			} else {
				// Citrus on a sprig: an orange or a lemon, its highlight, a leaf.
				float R = cell * 0.17;
				vec3 fc = mh(id + 3.3) < 0.6 ? lin(vec3(0.97, 0.52, 0.08)) : lin(vec3(0.98, 0.86, 0.2));
				d = length(v) - R;
				m = mix(fc, fc * 1.3 + 0.05, fill(length(v - vec2(-R, R) * 0.35) - R * 0.25, px));
				vec2 lq = v - vec2(R * 0.3, R * 0.9);
				float dl;
				vec3 lm = leaf(vec2(dot(lq, vec2(0.7, 0.7)), dot(lq, vec2(-0.7, 0.7))), R * 1.6, R * 0.45, leaf_mid, leaf_dark, dl);
				m = d < 0.0 ? m : lm;
				d = min(d, dl);
			}
			col = layer(col, m, d, px, layer_i == 0 ? 0.0 : cell * 0.02, pal(P, 6));
		}
	}
	return col;
}

// One band of folk-art geometry: `pat` picks the figure, (x, y) in units of the band's height.
float folk(float pat, vec2 q) {
	float tri = abs(fract(q.x) - 0.5) * 2.0;
	if (pat < 1.0) {
		// Zigzag.
		return step(abs(q.y - 0.5 - (tri - 0.5) * 0.5), 0.17);
	} else if (pat < 2.0) {
		// Stepped fret: a zigzag in steps.
		float st = floor(tri * 4.0) / 4.0;
		return step(q.y, 0.15 + st * 0.7);
	} else if (pat < 3.0) {
		// Diamonds with a diamond inside.
		float dd = abs(fract(q.x) - 0.5) + abs(q.y - 0.5);
		return step(dd, 0.42) - step(dd, 0.22) + step(dd, 0.1);
	} else if (pat < 4.0) {
		// Sawtooth triangles.
		return step(q.y, 1.0 - tri * 1.0) * step(0.1, q.y);
	} else {
		// Rosettes: a dot with four petals.
		vec2 f = vec2(fract(q.x) - 0.5, q.y - 0.5);
		float r = length(f);
		float th = atan(f.y, f.x);
		return step(r, 0.33 * (0.6 + 0.4 * abs(cos(th * 2.0)))) - step(r, 0.12) + step(r, 0.06);
	}
}

vec3 scene_folk(vec2 p, vec2 S, float s, float px, float bands_wanted) {
	float H = S.y;
	int P = int(mh1(s) * 2.0) == 0 ? 3 : 5;
	float n = max(1.0, floor(bands_wanted));
	float bh = H / n;
	float bi = floor(p.y / bh);
	float y = (p.y - bi * bh) / bh;
	float bs = s * 3.0 + bi * 1.7;
	float pat = floor(mh1(bs) * 5.0);
	// The band's ground deep, its figure bright, so a band reads from across the street.
	int ga[4] = int[4](0, 4, 5, 6);
	int fa[4] = int[4](1, 2, 3, 7);
	vec3 a = pal(P, ga[int(mh1(bs + 1.0) * 4.0)]);
	vec3 b = pal(P, fa[int(mh1(bs + 2.0) * 4.0)]);
	// The figures run along the band, a whole number of repeats across the design.
	float reps = max(1.0, floor(S.x / (bh * (0.8 + 0.5 * mh1(bs + 3.0)))));
	float x = p.x / S.x * reps;
	// A rule top and bottom of each band.
	float inner = (y - 0.12) / 0.76;
	float m = inner > 0.0 && inner < 1.0 ? folk(pat, vec2(x, inner)) : 0.0;
	float rule = step(abs(y - 0.06), 0.03) + step(abs(y - 0.94), 0.03);
	vec3 col = mix(a, b, clamp(m, 0.0, 1.0));
	col = mix(col, pal(P, 6), clamp(rule, 0.0, 1.0));
	return col;
}

vec3 scene_waves(vec2 p, vec2 S, float s, float px) {
	float H = S.y;
	int P = 6;
	float R = min(H * 0.2, 0.8);
	// Scallops: rings of radius R, 2R apart, each row R / 2 above the last and offset by R; a
	// lower row lies over the one above it, so each point takes the lowest ring that holds it.
	vec2 g = p / R;
	float j0 = floor((g.y - 1.0) / 0.5);
	float ring = -1.0;
	for (int j = 0; j <= 2; j++) {
		float jj = j0 + float(j);
		float cy = jj * 0.5;
		if (cy > g.y) {
			break;
		}
		float off = mod(jj, 2.0);
		float cx = floor((g.x - off + 1.0) / 2.0) * 2.0 + off;
		float dd = length(g - vec2(cx, cy));
		if (dd < 1.0) {
			ring = dd;
			break;
		}
	}
	if (ring < 0.0) {
		return pal(P, 0);
	}
	float k = floor(ring * 4.0);
	vec3 col = mix(pal(P, 0), pal(P, 1), k / 3.0);
	// The thin light line between rings, and the outer ring's edge.
	float f = fract(ring * 4.0);
	col = mix(col, pal(P, 7), 1.0 - smoothstep(0.05, 0.1, min(f, 1.0 - f)));
	col = mix(col, pal(P, 6), step(0.94, ring));
	return col;
}

vec3 paint_scene(float sc, vec2 p, vec2 S, float s, float px) {
	if (sc < 0.5) {
		return scene_coast(p, S, s, px);
	} else if (sc < 1.5) {
		return scene_mountains(p, S, s, px);
	} else if (sc < 2.5) {
		return scene_desert(p, S, s, px);
	} else if (sc < 3.5) {
		return scene_botanical(p, S, s, px);
	} else if (sc < 4.5) {
		return scene_folk(p, S, s, px, max(2.0, S.y / 1.4));
	}
	return scene_waves(p, S, s, px);
}

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM;
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(vp.xyz * (1.0 - depth_pull), 1.0);
}

void fragment() {
	float code = floor(v_custom.r + 0.5);
	float mode = floor(code / 16.0);
	float sc = code - mode * 16.0;
	float seed = v_custom.g * 97.13 + 1.0;
	float sub = floor(v_custom.a + 0.5);
	float substrate = mod(sub, 8.0);
	float wear = floor(sub / 8.0) / 7.0;
	vec2 uv = UV;
	vec2 p = vec2(uv.x * v_size.x, (1.0 - uv.y) * v_size.y);
	vec3 alb = vec3(0.5);
	float a = 1.0;
	float age = v_col.g;
	float rough = 0.86;
	float grain = 1.0;
	float px = max(length(fwidth(p)) * 0.75, 0.002);
	// The brush: every edge wobbles a centimetre or two, finer where the pixel allows.
	vec2 warp = (vec2(mfbm(p * 4.0 + seed), mfbm(p * 4.0 + seed + 17.0)) - 0.5) * 0.035
		+ (vec2(mnoise(p * 30.0 + seed), mnoise(p * 30.0 - seed)) - 0.5) * 0.008 * (1.0 - smoothstep(0.004, 0.02, px));
	if (mode > 0.5 && mode < 1.5) {
		// A ghost sign: the atlas cell, in a faded period palette, flaking off the brick.
		age = v_col.a;
		float cell = floor(v_custom.b + 0.5);
		vec2 c = vec2(mod(cell, 2.0), floor(cell / 2.0));
		vec2 auv = (c + clamp(uv, 0.002, 0.998)) / vec2(2.0, 8.0);
		vec3 m = texture(ghost_atlas, auv).rgb;
		int pick = int(seed * 13.0);
		vec3 field = lin(GHOST_FIELD[pick % 6]);
		vec3 ink = lin(GHOST_INK[(pick / 6) % 4]);
		if (pick % 6 == 5) {
			ink = lin(GHOST_INK[3]);
		}
		vec3 second = lin(GHOST_SECOND[(pick / 3) % 4]);
		if (length(second - field) < 0.15) {
			second = ink * 0.8;
		}
		alb = field;
		alb = mix(alb, second, m.b);
		alb = mix(alb, ink, m.g);
		float cover = max(m.r, max(m.g, m.b));
		// Sun-bleached chalky paint, most of the field gone; the lettering lasts longest (the
		// white lead paint of the period).
		vec3 chalk = vec3(dot(alb, vec3(0.3, 0.55, 0.15))) * 0.7 + lin(vec3(0.55, 0.5, 0.45)) * 0.35;
		alb = mix(alb, chalk, 0.25 + 0.35 * age);
		float flake = mfbm(p * vec2(9.0, 14.0) + seed) + 0.25 * mnoise(p * 60.0 + seed);
		float keep = smoothstep(0.2 + 0.35 * age, 0.32 + 0.35 * age, flake + m.g * 0.3);
		// The field held on as a stain; the white lead lettering stood up best.
		a = cover * keep * mix(mix(0.88, 0.68, age), mix(0.97, 0.88, age), max(m.g, m.b * 0.6));
		// Weather: rain runs down from the top, and the bottom rubbed by a century of things.
		a *= 1.0 - 0.4 * smoothstep(0.55, 0.85, mnoise(vec2(p.x * 3.0, p.y * 0.4) + seed));
		// Part of it painted over later in the wall's colour (a patch from a later tenant).
		if (mh1(seed + 5.0) < 0.45) {
			vec2 pc = vec2(v_size.x * mh1(seed + 6.0), v_size.y * 0.5);
			vec2 hb = vec2(v_size.x * (0.12 + 0.18 * mh1(seed + 7.0)), v_size.y * 0.7);
			float over = fill(sd_box(p + warp - pc, hb), px);
			vec3 wallc = lin(v_col.rgb);
			alb = mix(alb, mix(wallc, vec3(dot(wallc, vec3(0.3, 0.55, 0.15))), 0.3) * 1.08, over);
			a = mix(a, 0.7 * smoothstep(0.2, 0.5, mfbm(p * 2.0 + seed * 3.0) + 0.3), over);
		}
		rough = 0.92;
		grain = 1.2;
	} else if (mode > 1.5 && mode < 2.5) {
		// A painted crosswalk: `sc` is the district's pattern. x runs across the road, y across
		// the crossing; white edge lines along both long sides, as the code wants.
		float W = max(v_col.r, v_size.x);
		vec2 q = p + vec2(v_custom.b, 0.0);
		float edge = step(min(q.y, v_size.y - q.y), 0.3);
		float y = clamp((q.y - 0.3) / max(v_size.y - 0.6, 0.1), 0.0, 1.0);
		if (sc < 0.5) {
			// Rainbow: bars along the walk in six colours.
			float bar = floor(q.x / 0.62);
			int i = int(mod(bar, 6.0));
			vec3 rb[6] = vec3[6](vec3(0.85, 0.12, 0.12), vec3(0.95, 0.5, 0.08), vec3(0.97, 0.85, 0.15),
				vec3(0.1, 0.55, 0.25), vec3(0.12, 0.3, 0.75), vec3(0.45, 0.18, 0.6));
			alb = lin(rb[i]);
		} else if (sc < 1.5) {
			// Folk geometry across the walk.
			float pat = floor(mh1(seed) * 5.0);
			float m = folk(pat, vec2(q.x / max(v_size.y - 0.6, 0.5), y));
			alb = mix(pal(3, 3), pal(3, 0), m);
		} else if (sc < 2.5) {
			// Waves: scallops in blues.
			alb = scene_waves(q * 0.6, vec2(W, v_size.y), seed, px);
		} else {
			// Flowers on a bright ground.
			alb = scene_botanical(q, vec2(W, v_size.y * 1.4), seed, px);
		}
		alb = mix(alb, lin(vec3(0.93, 0.93, 0.9)), edge);
		// The paint wears through where the wheels run: lane-wide bands across the walk, the
		// tyres' two tracks in each, thinnest in the middle of the lane.
		float lane = fract(q.x / 3.4);
		float track = 1.0 - smoothstep(0.08, 0.2, min(abs(lane - 0.27), abs(lane - 0.73)));
		float worn = mfbm(p * vec2(0.8, 2.5) + seed) * 0.55 + track * (0.2 + 0.4 * age) * (0.6 + 0.4 * mnoise(p * vec2(0.5, 3.0) + seed));
		a = 1.0 - smoothstep(0.6, 0.85, worn) * 0.7;
		// Grit and the asphalt's pits through the paint.
		a *= 0.75 + 0.25 * step(0.25, mnoise(p * 45.0 + seed));
		alb *= 0.9 + 0.12 * mnoise(p * 8.0 + seed);
		rough = 0.75;
		grain = 1.3;
	} else {
		// A mural (mode 0), a cabinet's painted wrap (3) or a frieze (4).
		float W = max(v_col.r, v_size.x);
		vec2 S = vec2(W, v_size.y);
		vec2 q = p + vec2(v_custom.b, 0.0);
		vec2 qw = q + warp * (mode > 2.5 && mode < 3.5 ? 0.3 : 1.0);
		if (mode > 3.5) {
			alb = scene_folk(qw, S, seed, px, max(1.0, floor(S.y / 0.7)));
		} else {
			alb = paint_scene(sc, qw, S, seed, px);
			// A painted frame round some murals: a folk band, outlined.
			float bw = min(S.y, S.x) * 0.07;
			float e = min(min(q.x, S.x - q.x), min(q.y, S.y - q.y));
			if (mh1(seed + 21.0) < 0.45 && e < bw) {
				vec2 fq = q.y < bw || q.y > S.y - bw ? vec2(q.x, q.y < bw ? q.y : S.y - q.y) : vec2(q.y, q.x < bw ? q.x : S.x - q.x);
				float m = folk(floor(mh1(seed + 22.0) * 5.0), vec2(fq.x / bw, fq.y / bw));
				int P = 3;
				alb = mix(pal(P, 6), pal(P, int(mh1(seed + 23.0) * 4.0)), m);
				alb = mix(alb, pal(P, 7), step(abs(e - bw), bw * 0.08));
			}
		}
		// Brush strokes inside every area: a few percent of tone, along a slow stroke direction.
		float ang = mnoise(q * 0.7 + seed) * 3.14159;
		vec2 sd = vec2(cos(ang), sin(ang));
		float stroke = mnoise(vec2(dot(q, sd) * 2.0, dot(q, vec2(-sd.y, sd.x)) * 26.0) + seed);
		alb *= 0.95 + 0.09 * stroke * (1.0 - smoothstep(0.01, 0.04, px));
		// Sun fade: the colours chalk and lighten, the reds first.
		vec3 grey = vec3(dot(alb, vec3(0.3, 0.55, 0.15)));
		alb = mix(alb, grey * 0.85 + vec3(0.06), age * 0.45);
		alb.r = mix(alb.r, grey.r, age * 0.15);
		// The edge of the painted area: a primer line, not a tape line.
		float e2 = min(min(q.x, S.x - q.x), min(q.y, S.y - q.y));
		a = smoothstep(0.0, 0.02, e2 + (mnoise(q * 12.0 + seed) - 0.5) * 0.02) * (mode > 2.5 && mode < 3.5 ? 1.0 : 1.0);
		// Flaking: patches of wall show through, more with wear, most at the foot.
		float foot = 1.0 - smoothstep(0.0, 1.2, q.y);
		float flake = mfbm(q * vec2(1.6, 2.2) + seed * 1.3) + 0.12 * mnoise(q * 9.0 + seed);
		float t_peel = 0.95 - 0.35 * wear - 0.25 * foot * wear;
		a *= 1.0 - smoothstep(t_peel, t_peel + 0.05, flake);
		if (mode > 2.5 && mode < 3.5) {
			// Painted steel: smoother, a little gloss, no wall grain.
			rough = 0.55;
			grain = 0.25;
		}
	}
	// Substrate 4 is asphalt (the crosswalks): its grain is coarse; 5 is painted steel.
	if (use_screen && grain > 0.0) {
		vec2 spx = 5.0 / VIEWPORT_SIZE;
		vec3 w = vec3(0.3, 0.55, 0.15);
		float under = dot(texture(screen_tex, SCREEN_UV).rgb, w);
		float around = 0.25 * (dot(texture(screen_tex, SCREEN_UV + vec2(spx.x, spx.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(-spx.x, spx.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(spx.x, -spx.y)).rgb, w)
			+ dot(texture(screen_tex, SCREEN_UV + vec2(-spx.x, -spx.y)).rgb, w));
		float ratio = clamp(under / max(around, 0.01), 0.6, 1.4);
		alb *= mix(1.0, ratio, clamp(grain, 0.0, 1.0));
	}
	float dist = length(VERTEX);
	a *= 1.0 - smoothstep(fade_end * 0.8, fade_end, dist);
	ALBEDO = cs_out(alb);
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = substrate > 4.5 ? 0.5 : 0.35;
}
