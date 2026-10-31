// The corner store's opaque surfaces (CornerStoreKit), inside and out, on ONE material: what a
// surface is rides in the vertex colour's alpha (kind / 32, CornerStoreKit.K_*), its paint in the
// rgb as written (sRGB). UV is in metres (LandmarkGeo: along a wall and the height; (x, z) on a
// floor or ceiling, the store's own frame). Works in linear on both renderers (color_space).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D plaster_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// The plaster set's mean, so the texture adds grain without changing the paint.
uniform float plaster_mean = 0.38;
// The lightbox and its letters by day and after dark (times lamp_factor).
uniform float sign_day = 0.35;
uniform float sign_night = 1.5;
uniform float sign_cap = 0.7;
// The ceiling's light panels and the coolers' lit backs (always on: the store is open).
uniform float troffer_energy = 3.2;
uniform float cooler_energy = 1.9;
uniform float ceiling_bounce = 0.32;

global uniform float lamp_factor;

varying flat int kind;
varying vec3 local_pos;

const int K_STUCCO = 0;
const int K_PAINT = 1;
const int K_FLOOR = 2;
const int K_CEILING = 3;
const int K_TROFFER = 4;
const int K_ALUMINIUM = 5;
const int K_STEEL = 6;
const int K_SHELF = 7;
const int K_LAMINATE = 8;
const int K_SIGN = 9;
const int K_LETTERS = 10;
const int K_GLOW = 11;
const int K_RUBBER = 12;
const int K_TILE = 13;
const int K_CONCRETE = 14;
const int K_PEGBOARD = 15;
const int K_SCREEN = 16;
const int K_POSTER = 17;
const int K_NEON = 18;
const int K_CHROME = 19;
const int K_ROOF = 20;
const int K_WIRE = 21;
const int K_PRICE = 22;
const int K_MURAL = 23;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A grid's line, box-filtered: 1 on a line `w` wide every `p` metres.
float grid_line(float x, float p, float w) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x / p + 0.5) - 0.5) * p;
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, d);
}

// --- The side wall's hand-painted mural (K_MURAL) -------------------------------------------------
// LA corner stores paint their goods on the street wall: a row of panels, each a picture on a flat
// ground inside a painted border - a soda bottle, an ice cream cone, a can, a lotto star, a
// paleta, fruit. Drawn as signed distances in the panel's own metres (UV: metres along the wall
// and the height), outlined in dark paint, the edges wobbled by a brush noise, then faded and
// flaked to the stucco under it. Never words or a brand: pictures only.
const float MURAL_Y0 = 0.62;
const float MURAL_Y1 = 1.86;
const float MURAL_SLOT = 1.7;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float sd_star(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994, -0.587785252);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sd_tri_down(vec2 p, float w, float h) {
	// A cone point down: apex at (0, -h), the rim from (-w, 0) to (w, 0).
	vec2 q = vec2(abs(p.x), p.y);
	vec2 e = normalize(vec2(h, w));
	float side = dot(q - vec2(w, 0.0), e);
	return max(side, q.y);
}

// One picture: its fill colour and an outline distance; `id` picks it.
vec4 mural_icon(vec2 p, int id, float hsh) {
	vec3 col = vec3(0.0);
	float d = 1e3;
	if (id == 0) {
		// A soda bottle, tilted a little, with its label band and cap.
		float a = (hsh - 0.5) * 0.4;
		p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
		float body = sd_box(p - vec2(0.0, -0.12), vec2(0.14, 0.3), 0.08);
		float neck = sd_box(p - vec2(0.0, 0.26), vec2(0.05, 0.12), 0.03);
		d = min(body, neck);
		col = mix(vec3(0.55, 0.12, 0.08), vec3(0.15, 0.45, 0.18), step(0.5, hsh));
		if (abs(p.y + 0.12) < 0.08 && body < 0.0) col = vec3(0.95, 0.92, 0.85);
		if (p.y > 0.34) col = vec3(0.85, 0.75, 0.2);
	} else if (id == 1) {
		// An ice cream cone, two scoops.
		float cone = sd_tri_down(p - vec2(0.0, 0.02), 0.13, 0.42);
		float s1 = length(p - vec2(-0.05, 0.1)) - 0.14;
		float s2 = length(p - vec2(0.06, 0.26)) - 0.13;
		d = min(cone, min(s1, s2));
		col = vec3(0.82, 0.58, 0.28);
		if (s1 < 0.0) col = vec3(0.95, 0.6, 0.7);
		if (s2 < 0.0) col = vec3(0.98, 0.94, 0.82);
		if (cone < 0.0 && s1 > 0.0) {
			float hatch = abs(fract((p.x + p.y) * 14.0) - 0.5) + abs(fract((p.x - p.y) * 14.0) - 0.5);
			col *= 0.85 + 0.15 * step(0.5, hatch);
		}
	} else if (id == 2) {
		// A can, its top an ellipse.
		float body = sd_box(p, vec2(0.15, 0.25), 0.03);
		float top = length((p - vec2(0.0, 0.25)) * vec2(1.0, 3.2)) - 0.15;
		d = min(body, top);
		col = mix(vec3(0.12, 0.3, 0.62), vec3(0.85, 0.5, 0.1), step(0.5, hsh));
		if (top < 0.0) col = vec3(0.75);
		if (abs(p.y) < 0.05 && body < 0.0) col = vec3(0.95, 0.95, 0.9);
	} else if (id == 3) {
		// The lotto star, with a ring of rays.
		d = sd_star(p, 0.3, 0.45);
		col = vec3(0.98, 0.8, 0.15);
		float ang = atan(p.y, p.x);
		float ray = step(0.6, fract(ang / 6.2831853 * 16.0)) * step(0.35, length(p)) * step(length(p), 0.44);
		if (d > 0.0 && ray > 0.5) { d = -0.001; col = vec3(0.95, 0.4, 0.1); }
	} else if (id == 4) {
		// A paleta on its stick, a bite out of the corner.
		float bar = sd_box(p - vec2(0.0, 0.08), vec2(0.13, 0.26), 0.11);
		float bite = length(p - vec2(0.14, 0.32)) - 0.07;
		bar = max(bar, -bite);
		float stick = sd_box(p - vec2(0.0, -0.26), vec2(0.03, 0.1), 0.02);
		d = min(bar, stick);
		col = stick < 0.0 && bar > 0.0 ? vec3(0.85, 0.72, 0.5) : mix(vec3(0.9, 0.35, 0.45), vec3(0.45, 0.75, 0.3), step(0.5, hsh));
		if (bar < 0.0 && fract(p.y * 9.0 + hsh) < 0.15) col *= 1.15;
	} else {
		// Fruit: two oranges and a leaf.
		float o1 = length(p - vec2(-0.1, -0.06)) - 0.17;
		float o2 = length(p - vec2(0.13, 0.04)) - 0.15;
		float leaf = length((p - vec2(0.18, 0.24)) * vec2(1.0, 2.2)) - 0.08;
		d = min(min(o1, o2), leaf);
		col = leaf < 0.0 && o2 > 0.0 ? vec3(0.2, 0.5, 0.15) : vec3(0.95, 0.52, 0.08);
		float dimple = noise2(p * 60.0);
		col *= 0.92 + 0.12 * dimple;
	}
	return vec4(col, d);
}

vec3 mural(vec2 uv, vec3 bg, out float painted) {
	float slot = floor(uv.x / MURAL_SLOT);
	vec2 c = vec2((slot + 0.5) * MURAL_SLOT, (MURAL_Y0 + MURAL_Y1) * 0.5);
	vec2 p = uv - c;
	// The ground colour picks the pictures; rounded, since an interpolated vertex colour wobbles in
	// its last bits pixel to pixel and a hash of it would pick a new picture every column.
	vec3 bk = floor(bg * 32.0 + 0.5);
	float hsh = hash21(vec2(slot, bk.r * 31.0 + bk.g * 7.0 + bk.b * 3.0));
	// The brush: every edge wobbles a few millimetres.
	float wob = (noise2(uv * 24.0) - 0.5) * 0.012 + (noise2(uv * 5.0) - 0.5) * 0.01;
	vec2 hb = vec2(MURAL_SLOT * 0.5 - 0.09, (MURAL_Y1 - MURAL_Y0) * 0.5);
	float panel = sd_box(p, hb, 0.04) + wob;
	float border = abs(panel + 0.05) - 0.025;
	// Each panel's ground its own shade of the wall's paint.
	vec3 ground = mix(bg, bg * vec3(1.15, 1.05, 0.9), hsh);
	int id = (int(slot) + int(hsh * 6.0)) % 6;
	vec4 ic = mural_icon(p / 1.3, id, fract(hsh * 7.3));
	float fw = max(fwidth(ic.a), 1e-4);
	float fill = 1.0 - smoothstep(-fw, fw, ic.a + wob);
	float line = 1.0 - smoothstep(0.012 - fw, 0.012 + fw, abs(ic.a + wob));
	vec3 col = ground;
	// A painted shadow down and to the right of the picture.
	vec4 sh = mural_icon((p - vec2(0.045, -0.04)) / 1.3, id, fract(hsh * 7.3));
	col *= 1.0 - 0.25 * (1.0 - smoothstep(-fw, fw, sh.a));
	col = mix(col, ic.rgb, fill);
	col = mix(col, vec3(0.06, 0.05, 0.05), line);
	float bfw = max(fwidth(border), 1e-4);
	col = mix(col, vec3(0.08, 0.07, 0.07), 1.0 - smoothstep(-bfw, bfw, border));
	painted = 1.0 - smoothstep(-0.004, 0.004, panel);
	// Sun-faded toward the top, flaked off in patches to the stucco under it.
	col = mix(col, col * 0.75 + vec3(0.2), smoothstep(MURAL_Y0, MURAL_Y1, uv.y) * 0.15);
	float flake = step(0.8, noise2(uv * 5.0) * 0.75 + noise2(uv * 23.0) * 0.25);
	painted *= 1.0 - flake;
	return col;
}

void vertex() {
	kind = int(round(COLOR.a * 32.0));
	local_pos = VERTEX;
}

void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec2 uv = UV;
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	if (kind == K_STUCCO) {
		vec3 tx = cs_in(texture(plaster_tex, uv / 2.4).rgb);
		float l = dot(tx, vec3(0.333)) / plaster_mean;
		base *= mix(1.0, clamp(l, 0.6, 1.35), 0.7);
		// Splash grime along the foot and a faint run down from the coping.
		float foot = 1.0 - smoothstep(0.0, 0.7, uv.y + noise2(uv * vec2(1.3, 0.4)) * 0.25);
		base *= 1.0 - 0.28 * foot;
		base *= 0.92 + 0.08 * noise2(uv * vec2(0.5, 0.18));
		// The plaster's relief as a slope off the face (the mesh carries no tangents).
		vec2 nm = texture(plaster_nrm, uv / 2.4).rg * 2.0 - 1.0;
		vec3 t = normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
		vec3 b = cross(t, NORMAL);
		NORMAL = normalize(NORMAL + (t * nm.x + b * nm.y) * 0.35);
		rough = 0.92;
	} else if (kind == K_PAINT) {
		base *= 0.95 + 0.05 * noise2(uv * 3.0);
		// A scuffed band at trolley height along the walls.
		base *= 1.0 - 0.08 * smoothstep(0.35, 0.1, abs(uv.y - 0.25)) * noise2(uv * vec2(4.0, 1.0));
		rough = 0.75;
	} else if (kind == K_FLOOR) {
		vec2 t = floor(uv / 0.305);
		float chk = mod(t.x + t.y, 2.0);
		float h = hash21(t);
		vec3 dark = base * vec3(0.42, 0.44, 0.47);
		base = mix(base, dark, chk) * (0.93 + 0.1 * h);
		// The vinyl's own chips.
		base *= 0.92 + 0.12 * noise2(uv * 26.0);
		// Grout and the tile edges hold the dirt; a few tiles are newer, a few cracked.
		float seam = grid_line(uv.x, 0.305, 0.006) + grid_line(uv.y, 0.305, 0.006);
		base = mix(base, base * vec3(0.55, 0.5, 0.44), clamp(seam, 0.0, 1.0) * 0.8);
		vec2 f = fract(uv / 0.305);
		float edge = 1.0 - smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		base *= 1.0 - 0.12 * edge;
		// Wear paths: where people walk the wax is gone and the tiles are greyed and scuffed - the
		// noise follows long strokes, and heel marks cross them.
		float path = smoothstep(0.45, 0.8, noise2(uv * vec2(0.55, 0.22)) * 0.6 + noise2(uv * 0.9) * 0.4);
		float scuff = smoothstep(0.82, 0.95, noise2(vec2(uv.x * 9.0 + uv.y * 3.0, uv.y * 1.2)));
		base = mix(base, base * vec3(0.78, 0.76, 0.72) + 0.03, path * 0.6);
		base *= 1.0 - 0.35 * scuff;
		// Dirt drifted into the corners near the walls (the room's floor UV is the store frame).
		rough = mix(0.22, 0.62, max(path, noise2(uv * 0.7) * 0.5));
	} else if (kind == K_CEILING) {
		float bars = max(grid_line(uv.x, 0.61, 0.024), grid_line(uv.y, 1.22, 0.024));
		float speck = noise2(uv * 60.0);
		base *= mix(0.9 + 0.1 * speck, 0.82, bars);
		rough = 0.95;
		// The light panels' bounce off the floor and shelves: a lit ceiling, not the sky's ground
		// colour (the ambient a ceiling sees from below is the street's brown).
		emit = base * ceiling_bounce;
	} else if (kind == K_TROFFER) {
		// A lens of small square cells in a white frame; each panel its own age (a hash of the
		// panel's cell in the store frame), one now and then with a tired tube at one end.
		float cell = max(grid_line(uv.x, 0.06, 0.006), grid_line(uv.y, 0.06, 0.006));
		vec2 pc = floor(local_pos.xz / 2.4);
		float age = hash21(pc + 7.3);
		float tube = age < 0.18 ? mix(0.45, 1.0, smoothstep(-0.6, 0.6, fract(local_pos.x / 2.4) * 2.0 - 1.0)) : 1.0;
		vec3 lightc = mix(vec3(1.0, 0.97, 0.91), vec3(0.93, 0.98, 1.0), step(0.7, age));
		emit = lightc * troffer_energy * (0.8 + 0.25 * age) * tube * (1.0 - 0.35 * cell);
		base = vec3(0.9);
		rough = 0.6;
	} else if (kind == K_ALUMINIUM) {
		metal = 0.85;
		rough = 0.36;
		base *= 0.96 + 0.04 * noise2(vec2(uv.x * 40.0, uv.y * 2.0));
	} else if (kind == K_STEEL) {
		metal = 0.5;
		rough = 0.55;
		base *= 0.9 + 0.2 * noise2(uv * 9.0);
	} else if (kind == K_SHELF) {
		rough = 0.45;
		metal = 0.2;
	} else if (kind == K_LAMINATE) {
		float grain = noise2(vec2(uv.x * 2.0, uv.y * 40.0));
		base *= 0.9 + 0.15 * grain;
		rough = 0.4;
	} else if (kind == K_SIGN) {
		emit = base * (sign_day + sign_night * lamp);
		// A lit face: bright, but a red brighter than ~1 turns salmon pink through AgX, so a
		// red-heavy face keeps green at a share of red (it reads red-orange, as a real lightbox
		// does) and the whole is held under `sign_cap`.
		emit.g = max(emit.g, emit.r * 0.1 * smoothstep(0.6, 1.6, emit.r));
		emit /= max(1.0, max(emit.r, max(emit.g, emit.b)) / sign_cap);
		// Held at 0.7 (it was 1.3): on Forward+ the face plus its own lit albedo went through AgX
		// as peach (247, 188, 132) at 21:00 against (232, 46, 19) at noon (fwd-review-d).
		base *= 0.3;
		rough = 0.25;
	} else if (kind == K_LETTERS) {
		emit = base * (sign_day * 1.6 + sign_night * 1.3 * lamp);
		emit.g = max(emit.g, emit.r * 0.3 * smoothstep(0.6, 1.6, emit.r));
		emit /= max(1.0, max(emit.r, max(emit.g, emit.b)) / (sign_cap * 1.8));
		base *= 0.6;
		rough = 0.3;
	} else if (kind == K_GLOW) {
		emit = vec3(0.95, 0.98, 1.0) * cooler_energy;
		base = vec3(0.9);
	} else if (kind == K_RUBBER) {
		rough = 0.9;
	} else if (kind == K_TILE) {
		float g = max(grid_line(uv.x, 0.1, 0.004), grid_line(uv.y, 0.1, 0.004));
		base *= mix(0.95 + 0.1 * hash21(floor(uv / 0.1)), 0.45, g);
		rough = mix(0.15, 0.8, g);
	} else if (kind == K_CONCRETE) {
		base *= 0.85 + 0.25 * noise2(uv * 3.0) * noise2(uv * 0.7);
		rough = 0.92;
	} else if (kind == K_PEGBOARD) {
		vec2 c = fract(uv / 0.0254) - 0.5;
		float hole = 1.0 - smoothstep(0.12, 0.2, length(c));
		float fine = 1.0 - smoothstep(0.002, 0.006, fwidth(uv.x));
		base *= 1.0 - 0.7 * hole * fine - 0.12 * (1.0 - fine);
		rough = 0.6;
	} else if (kind == K_SCREEN) {
		float rows = 0.75 + 0.25 * step(0.5, fract(uv.y * 30.0));
		emit = base * 1.4 * rows;
		base = vec3(0.02);
		rough = 0.1;
	} else if (kind == K_POSTER) {
		rough = 0.65;
	} else if (kind == K_NEON) {
		emit = base * (2.2 + 2.0 * lamp);
		base *= 0.4;
	} else if (kind == K_CHROME) {
		metal = 1.0;
		rough = 0.06;
	} else if (kind == K_ROOF) {
		base *= 0.85 + 0.2 * noise2(uv * 0.6);
		rough = 0.9;
	} else if (kind == K_PRICE) {
		// The shelf edge's price strip: white tags every few facings, a yellow sale tag now and
		// then, a line of small print and a barcode-ish block on each (UV metres along the strip).
		float slot = floor(uv.x / 0.16);
		float f = fract(uv.x / 0.16);
		float hs = hash21(vec2(slot, floor(uv.y * 7.0) + local_pos.z * 3.1));
		float tag = step(0.06, f) * step(f, 0.62) * step(0.25, hs);
		vec3 paper = hs > 0.88 ? vec3(0.95, 0.78, 0.12) : vec3(0.96, 0.96, 0.94);
		vec3 strip = vec3(0.10, 0.10, 0.11);
		float fine = 1.0 - smoothstep(0.004, 0.012, fwidth(uv.x));
		float ink = step(0.12, f) * step(f, 0.4) * step(0.5, fract(uv.y * 40.0 + hs)) * fine;
		base = mix(strip, mix(paper, vec3(0.08), ink * 0.7), mix(0.7, tag, fine));
		rough = 0.4;
	} else if (kind == K_MURAL) {
		// Paint on the stucco: a sheet a few millimetres off the wall, cut away (discard) round the
		// panels and where it has flaked, so the wall's own plaster shows there.
		float painted = 0.0;
		vec3 m = mural(uv, base, painted);
		if (painted < 0.5) {
			discard;
		}
		vec3 tx = cs_in(texture(plaster_tex, uv / 2.4).rgb);
		float l = dot(tx, vec3(0.333)) / plaster_mean;
		base = m * mix(1.0, clamp(l, 0.85, 1.12), 0.4);
		vec2 nm = texture(plaster_nrm, uv / 2.4).rg * 2.0 - 1.0;
		vec3 t = normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
		vec3 b = cross(t, NORMAL);
		NORMAL = normalize(NORMAL + (t * nm.x + b * nm.y) * 0.3);
		rough = 0.72;
	} else if (kind == K_WIRE) {
		metal = 0.7;
		rough = 0.4;
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
