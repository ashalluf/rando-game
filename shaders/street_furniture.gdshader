shader_type spatial;
render_mode cull_back;

// Street furniture (scripts/world/street_furniture.gd): hydrants, meters, pay stations, the bus
// bench with its painted ad, the perforated downtown bin, residential carts, bike racks and kerb
// planters. One material for all of it, so each kind is one MultiMesh draw a chunk.
//
// * COLOR.a says what a vertex is: kind = floor(COLOR.a * 16), StreetFurniture.K_*. COLOR.rgb is
//   the part's own colour (sRGB). The instance colour is white.
// * INSTANCE_CUSTOM: rgb the instance's paint (sRGB) for the painted kinds, the bench's ad in .r
//   (index = floor(r * 16)); .a the wear (0 fresh .. 1 old).
// * UV is metres on the surface (round a lathe: arc length, up it: height); a label, a screen, the
//   ad: 0..1 over the face, v down. UV2.x is the label's id (StreetFurniture.L_*).
// * Colour space: everything is worked in linear (color_space.gdshaderinc): vertex colours and
//   instance data arrive raw (sRGB) on both renderers and are decoded here; the ad atlas is a
//   source_color texture and goes through cs_in().
// * Fine detail (paint chips, perforations, spangle, aggregate, print) fades to its average once
//   it is under a pixel, or it shimmers.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D ad_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float ad_rows = 8.0;
// Perforations of the mesh bin: hole pitch and radius (m).
uniform float perf_pitch = 0.021;
uniform float perf_radius = 0.0072;
// How much the wear shows: paint chips, sun fade, grime.
uniform float chip_gain = 1.0;
uniform float grime_gain = 1.0;
uniform float screen_glow = 0.9;
// 1: paint the view-space normal (front faces) / red (back faces), for checking the meshes.
uniform int debug_mode = 0;

global uniform float road_wetness;
global uniform float lamp_factor;
global uniform vec3 origin_shift;

const float K_PAINT = 0.0;
const float K_PAINT_V = 1.0;
const float K_GALV = 2.0;
const float K_STEEL = 3.0;
const float K_RUBBER = 4.0;
const float K_CONCRETE = 5.0;
const float K_PERF = 6.0;
const float K_LINER = 7.0;
const float K_HDPE = 8.0;
const float K_AD = 9.0;
const float K_SCREEN = 10.0;
const float K_SOIL = 11.0;
const float K_LABEL = 12.0;
const float K_SOLAR = 13.0;
const float K_GLASS = 14.0;
const float K_BRASS = 15.0;

varying float v_kind;
varying vec3 v_col;
varying vec3 v_paint;
varying float v_wear;
varying float v_ad;
varying vec3 v_local;
varying vec3 v_lnormal;
varying float v_seed;
varying float v_tag;

float sf_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float sf_hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float sf_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(sf_hash3(i), sf_hash3(i + vec3(1, 0, 0)), f.x), mix(sf_hash3(i + vec3(0, 1, 0)), sf_hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(sf_hash3(i + vec3(0, 0, 1)), sf_hash3(i + vec3(1, 0, 1)), f.x), mix(sf_hash3(i + vec3(0, 1, 1)), sf_hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float sf_fbm(vec3 p) {
	return sf_noise(p) * 0.55 + sf_noise(p * 2.07 + 7.1) * 0.3 + sf_noise(p * 4.3 + 3.3) * 0.15;
}

// How much of a pattern with features `size` metres across survives at this pixel (1 crisp).
float sf_keep(float size) {
	float fw = length(fwidth(v_local));
	return 1.0 - smoothstep(size * 0.35, size * 1.1, fw);
}

vec3 lin(vec3 c) {
	return cs_srgb_to_linear(c);
}

// A line of pseudo type along x (0..1 units of `chars`), 1 = ink.
float sf_words(float x, float row, float seed, float chars) {
	float cx = x * chars;
	float word = floor(cx / 5.0 + sf_hash(vec2(row, seed)) * 3.0);
	float gap = step(0.8, fract(cx / 5.0 + sf_hash(vec2(row, seed)) * 3.0));
	float letter = step(0.22, fract(cx)) * step(0.28, sf_hash(vec2(floor(cx), row + seed)));
	return (1.0 - gap) * mix(1.0, letter, 0.6) * step(0.1, sf_hash(vec2(word, row * 1.7 + seed)));
}

float sf_box(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

// A blocky "P" in a unit square (v down), 1 = ink.
float sf_glyph_p(vec2 p) {
	float stem = sf_box(p, vec2(0.24, 0.12), vec2(0.4, 0.88));
	vec2 c = vec2(0.47, 0.34);
	float d = length((p - c) * vec2(1.0, 1.08));
	float bowl = step(d, 0.24) * step(0.11, d) * step(0.4, p.x);
	float bar = sf_box(p, vec2(0.24, 0.1), vec2(0.5, 0.18)) + sf_box(p, vec2(0.24, 0.5), vec2(0.5, 0.58));
	return clamp(stem + bowl + bar, 0.0, 1.0);
}

void vertex() {
	v_kind = floor(COLOR.a * 16.0);
	v_col = lin(COLOR.rgb);
	v_paint = lin(INSTANCE_CUSTOM.rgb);
	v_wear = INSTANCE_CUSTOM.a;
	v_ad = INSTANCE_CUSTOM.r;
	v_local = VERTEX;
	v_lnormal = NORMAL;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + origin_shift;
	v_seed = sf_hash(floor(w.xz * 4.0) * 0.173 + 0.31);
	v_tag = UV2.x;
}

// Old paint over cast iron or steel: chalky fade, chips to dark iron with rust round them, rust
// bleeding down from the chips, grime from the pavement.
vec3 sf_worn_paint(vec3 paint, float wear, out float rough, out float metal) {
	vec3 p = v_local * vec3(1.0, 1.0, 1.0) + v_seed * 17.0;
	float keep = sf_keep(0.005);
	// Sun and age: the paint chalks, lightens and loses its colour.
	float lum = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(paint, mix(vec3(lum), paint, 0.55) * 1.12 + 0.02, wear * 0.55);
	// Chips: where a fine noise passes a threshold that drops with wear, more on edges and low down.
	// Two scales: fine flecks everywhere, and a coarse field that gathers them into worn patches.
	float n = sf_fbm(p * 85.0) * 0.7 + sf_fbm(p * 9.0 + 5.0) * 0.3;
	float edge = 1.0 - abs(v_lnormal.y);
	float chip_t = 1.0 - wear * chip_gain * (0.27 + 0.1 * edge + 0.14 * (1.0 - smoothstep(0.0, 0.3, v_local.y)));
	float chip = smoothstep(chip_t, chip_t + 0.03, n) * keep + (1.0 - keep) * clamp((1.0 - chip_t) * 0.6, 0.0, 0.3);
	float rustn = sf_fbm(p * 11.0 + 3.0);
	vec3 iron = mix(vec3(0.035, 0.032, 0.03), vec3(0.16, 0.06, 0.022), smoothstep(0.35, 0.7, rustn));
	// Rust halo round each chip and runs below them.
	float halo = smoothstep(chip_t - 0.1, chip_t, n) * (1.0 - chip) * wear;
	float run = smoothstep(0.62, 0.9, sf_fbm(vec3(p.x * 30.0, p.y * 4.0, p.z * 30.0))) * wear * 0.6 * keep;
	col = mix(col, col * vec3(0.62, 0.42, 0.28), clamp(halo * 0.8 + run, 0.0, 1.0));
	col = mix(col, iron, chip);
	rough = mix(mix(0.42, 0.72, wear), 0.8, chip);
	metal = 0.0;
	return col;
}

vec3 sf_label(vec2 uv, float id, vec3 under, out float ink_rough) {
	ink_rough = 0.45;
	float keep = sf_keep(0.004);
	if (id < 0.5) {
		// Meter: blue band "PAY", white below with three lines and a phone icon block.
		vec3 c = vec3(0.92);
		if (uv.y < 0.42) {
			c = lin(vec3(0.08, 0.32, 0.64));
			float t = sf_words(uv.x * 0.8 + 0.1, 1.0, 3.0, 9.0) * sf_box(uv, vec2(0.1, 0.12), vec2(0.9, 0.32));
			c = mix(c, vec3(0.95), t * keep + 0.25 * t * (1.0 - keep));
		} else {
			for (int i = 0; i < 2; i++) {
				float y0 = 0.52 + float(i) * 0.22;
				float t = sf_words(uv.x, float(i) + 4.0, 7.0, 18.0) * sf_box(uv, vec2(0.06, y0), vec2(0.94, y0 + 0.12));
				c = mix(c, vec3(0.04), t * keep * 0.9 + (1.0 - keep) * t * 0.3);
			}
		}
		return c;
	} else if (id < 1.5) {
		// Pay station instructions: a blue head, three numbered steps.
		vec3 c = vec3(0.9, 0.9, 0.88);
		if (uv.y < 0.18) {
			c = lin(vec3(0.08, 0.3, 0.62));
			float t = sf_words(uv.x, 9.0, 1.0, 10.0) * sf_box(uv, vec2(0.08, 0.05), vec2(0.92, 0.13));
			c = mix(c, vec3(0.95), t * keep);
		} else {
			for (int i = 0; i < 3; i++) {
				float y0 = 0.24 + float(i) * 0.25;
				vec2 cc = vec2(0.13, y0 + 0.07);
				float dot_ = step(length((uv - cc) * vec2(1.25, 1.0)), 0.06);
				c = mix(c, lin(vec3(0.08, 0.3, 0.62)), dot_);
				for (int j = 0; j < 3; j++) {
					float yy = y0 + float(j) * 0.055;
					float t = sf_words(uv.x, float(i * 3 + j) + 11.0, 5.0, 22.0) * sf_box(uv, vec2(0.25, yy), vec2(0.92 - float(j) * 0.12, yy + 0.032));
					c = mix(c, vec3(0.03), t * keep * 0.85 + (1.0 - keep) * t * 0.25);
				}
			}
		}
		return c;
	} else if (id < 2.5) {
		// The cart's hot-stamped lid: city name and a line, light grey on the plastic.
		float t = sf_words(uv.x, 2.0, 21.0, 12.0) * sf_box(uv, vec2(0.08, 0.2), vec2(0.92, 0.42));
		t += sf_words(uv.x, 3.0, 29.0, 20.0) * sf_box(uv, vec2(0.18, 0.56), vec2(0.82, 0.68));
		float ring = step(abs(length((uv - vec2(0.5, 0.85)) * vec2(2.4, 1.0)) - 0.09), 0.02);
		ink_rough = 0.55;
		return mix(under, vec3(0.62), clamp(t + ring, 0.0, 1.0) * (keep * 0.85 + 0.15));
	} else if (id < 3.5) {
		// The hydrant's stencilled number, blue on the paint.
		float t = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 q = vec2(uv.x * 4.0 - float(i), uv.y);
			float h = sf_hash(vec2(float(i), 5.0 + v_seed * 31.0));
			t += sf_box(q, vec2(0.18, 0.12), vec2(0.82, 0.88)) * (1.0 - sf_box(q, vec2(0.38, 0.3 + h * 0.2), vec2(0.62, 0.42 + h * 0.3))) * step(0.15, h);
		}
		ink_rough = 0.6;
		return mix(under, lin(vec3(0.12, 0.2, 0.42)), clamp(t, 0.0, 1.0) * (keep * 0.8 + 0.1));
	}
	// 5: the white "P" on blue.
	vec3 c = lin(vec3(0.08, 0.3, 0.66));
	return mix(c, vec3(0.95), sf_glyph_p(uv));
}

void fragment() {
	vec3 alb = v_col;
	float rough = 0.6;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	float porous = 0.0;
	float k = floor(v_kind + 0.5);
	float wear = v_wear;
	if (k == K_PAINT || k == K_PAINT_V) {
		vec3 paint = k == K_PAINT ? v_paint * v_col : v_col;
		alb = sf_worn_paint(paint, k == K_PAINT ? wear : wear * 0.5, rough, metal);
	} else if (k == K_GALV) {
		// Spangle: crystal grains a few cm across, each its own grey; dull white rust with age.
		vec3 q = v_local * 22.0 + v_seed * 9.0;
		vec3 cell = floor(q);
		float g = sf_hash3(cell) * sf_keep(0.04) + 0.5 * (1.0 - sf_keep(0.04));
		alb = v_col * (0.78 + 0.22 * g);
		float wr = smoothstep(0.55, 0.85, sf_fbm(v_local * 9.0 + 4.0)) * wear;
		alb = mix(alb, vec3(0.7, 0.7, 0.68), wr * 0.7);
		metal = mix(0.85, 0.2, wr);
		rough = mix(0.32 + 0.12 * g, 0.75, wr);
	} else if (k == K_STEEL) {
		alb = v_col;
		metal = 1.0;
		rough = 0.28 + 0.1 * sf_noise(v_local * vec3(4.0, 200.0, 4.0)) * sf_keep(0.01);
	} else if (k == K_BRASS) {
		alb = mix(lin(vec3(0.78, 0.6, 0.3)), lin(vec3(0.35, 0.32, 0.22)), wear * 0.6);
		metal = 1.0;
		rough = 0.35 + wear * 0.25;
	} else if (k == K_RUBBER) {
		alb = v_col;
		rough = 0.72;
	} else if (k == K_CONCRETE) {
		// Cast concrete: aggregate speckle, a blotchy cure, stains with age.
		float keep = sf_keep(0.006);
		float agg = sf_hash3(floor(v_local * 160.0 + v_seed * 13.0));
		float blot = sf_fbm(v_local * 3.0 + v_seed * 5.0);
		alb = v_col * (0.88 + 0.18 * blot) * (1.0 + (agg - 0.5) * 0.22 * keep);
		float stain = smoothstep(0.55, 0.85, sf_fbm(v_local * vec3(6.0, 1.5, 6.0) + 2.0)) * (0.3 + 0.7 * wear);
		alb *= 1.0 - stain * 0.3;
		rough = 0.9;
		porous = 1.0;
	} else if (k == K_PERF) {
		// Perforated steel, powder coated: the holes are cut where they are bigger than a pixel,
		// and averaged into a darker sheet past that.
		// Round the bin by angle (both walls' holes line up), up it by height.
		vec2 puv = vec2(atan(v_local.z, v_local.x) * 0.3, v_local.y);
		vec2 q = puv / perf_pitch;
		float row = floor(q.y);
		q.x += mod(row, 2.0) * 0.5;
		vec2 f = fract(q) - 0.5;
		float d = length(f) * perf_pitch;
		float fw = max(fwidth(v_local.y), length(fwidth(v_local.xz)));
		float open_area = 3.14159 * perf_radius * perf_radius / (perf_pitch * perf_pitch);
		if (fw < perf_pitch * 0.32 && d < perf_radius) {
			discard;
		}
		float far_mix = smoothstep(perf_pitch * 0.2, perf_pitch * 0.32, fw);
		alb = sf_worn_paint(v_paint, wear * 0.6, rough, metal);
		alb = mix(alb, alb * (1.0 - open_area) + vec3(0.01) * open_area, far_mix);
		rough = mix(0.5, 0.75, wear);
	} else if (k == K_LINER) {
		float wr = sf_fbm(v_local * vec3(14.0, 5.0, 14.0));
		alb = v_col * (0.8 + 0.4 * wr);
		rough = 0.32 + 0.2 * wr;
	} else if (k == K_HDPE) {
		// Moulded plastic: a fine stipple, sun fade with age, scuffs and road dirt low down.
		float keep = sf_keep(0.004);
		float st = sf_noise(v_local * 400.0) * keep + 0.5 * (1.0 - keep);
		float lum = dot(v_paint, vec3(0.2126, 0.7152, 0.0722));
		alb = mix(v_paint, mix(vec3(lum), v_paint, 0.6) + 0.025, wear * 0.6);
		alb *= 0.94 + 0.08 * st;
		float scuff = smoothstep(0.7, 0.92, sf_fbm(v_local * vec3(9.0, 30.0, 9.0) + v_seed * 11.0)) * (0.3 + wear);
		alb = mix(alb, alb * 0.7 + 0.03, scuff * 0.5);
		rough = 0.58 + 0.12 * wear + 0.1 * scuff;
	} else if (k == K_AD) {
		// The bench ad, painted on the concrete: faded by the sun, chipped where the paint lets go,
		// grimy along its foot, the odd scuff.
		float ad = floor(v_ad * 16.0);
		vec2 uv = vec2(UV.x, (ad + clamp(UV.y, 0.002, 0.998)) / ad_rows);
		vec3 art = cs_in(texture(ad_atlas, uv).rgb);
		float lum = dot(art, vec3(0.2126, 0.7152, 0.0722));
		art = mix(art, mix(vec3(lum), art, 0.7) * 1.06 + 0.03, wear * 0.5);
		float keep = sf_keep(0.01);
		float n = sf_fbm(v_local * 26.0 + v_seed * 7.0);
		float peel = smoothstep(1.0 - wear * 0.22, 1.02 - wear * 0.22, n) * keep;
		alb = mix(art, lin(vec3(0.62, 0.61, 0.58)), peel);
		float foot = 1.0 - smoothstep(0.0, 0.25, 1.0 - UV.y);
		alb *= 1.0 - foot * 0.18 * (0.4 + wear);
		rough = 0.62;
	} else if (k == K_SCREEN) {
		// LCD: a dark panel with a lit layout; the pay station's (tag 1) brighter.
		vec2 uv = UV;
		float keep = sf_keep(0.003);
		float lines = 0.0;
		for (int i = 0; i < 3; i++) {
			float y0 = 0.18 + float(i) * 0.25;
			lines += sf_words(uv.x, float(i) + v_tag * 7.0, 2.0 + floor(v_seed * 9.0), 10.0) * sf_box(uv, vec2(0.08, y0), vec2(0.92, y0 + 0.14));
		}
		lines = lines * keep + 0.3 * (1.0 - keep) * lines;
		vec3 bg = v_tag > 0.5 ? lin(vec3(0.04, 0.12, 0.22)) : lin(vec3(0.12, 0.16, 0.13));
		vec3 ink = v_tag > 0.5 ? vec3(0.85, 0.92, 1.0) : lin(vec3(0.02, 0.03, 0.03));
		vec3 lit = mix(bg, ink, clamp(lines, 0.0, 1.0));
		alb = lit * 0.25;
		em = (v_tag > 0.5 ? lit * 0.9 : lit * 0.35) * screen_glow * (0.4 + 0.6 * lamp_factor);
		if (v_col.r < 0.9) {
			em = v_col * 0.6;
		}
		rough = 0.12;
	} else if (k == K_SOIL) {
		float n = sf_fbm(v_local * 30.0);
		alb = v_col * (0.6 + 0.6 * n);
		rough = 0.95;
		porous = 1.0;
	} else if (k == K_LABEL) {
		float ir;
		vec3 under = v_tag > 2.5 && v_tag < 3.5 ? v_paint : (v_tag > 1.5 && v_tag < 2.5 ? v_paint : vec3(0.9));
		alb = sf_label(UV, v_tag, under, ir);
		float lum = dot(alb, vec3(0.2126, 0.7152, 0.0722));
		alb = mix(alb, vec3(lum) * 1.05, wear * 0.3);
		rough = ir;
	} else if (k == K_SOLAR) {
		vec2 q = UV * vec2(8.0, 5.0);
		vec2 f = abs(fract(q) - 0.5);
		float grid = step(0.44, max(f.x, f.y)) * sf_keep(0.006);
		float bus = step(abs(fract(q.x * 3.0) - 0.5), 0.03) * sf_keep(0.003);
		alb = mix(lin(vec3(0.03, 0.05, 0.12)), lin(vec3(0.55, 0.57, 0.6)), max(grid, bus * 0.7));
		rough = 0.12;
		metal = 0.3;
	} else if (k == K_GLASS) {
		alb = v_col * 0.4;
		rough = 0.06;
	}
	// Grime from the pavement up, heavier with age (not on screens and labels).
	if (k != K_SCREEN && k != K_SOLAR && k != K_GLASS) {
		float g = (1.0 - smoothstep(0.0, 0.32, v_local.y)) * (0.12 + 0.4 * wear) * grime_gain;
		g *= 0.7 + 0.6 * sf_noise(v_local * 18.0);
		alb = mix(alb, alb * vec3(0.55, 0.5, 0.44), clamp(g, 0.0, 1.0));
	}
	// Rain: darker porous faces, a film of water on what faces the sky.
	float wet = clamp(road_wetness, 0.0, 1.0);
	if (wet > 0.01) {
		float up = smoothstep(0.2, 0.9, v_lnormal.y);
		alb *= 1.0 - wet * (0.12 + 0.25 * porous);
		rough = mix(rough, 0.08, wet * (0.35 + 0.55 * up));
	}
	if (debug_mode == 1) {
		alb = FRONT_FACING ? (NORMAL * 0.5 + 0.5) * 0.8 : vec3(1.0, 0.0, 0.0);
		em = alb;
		alb = vec3(0.0);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(em);
}
