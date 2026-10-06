shader_type spatial;
// The walk of fame (StarBoulevard): the band of terrazzo squares down the boulevard's pavements
// with a coral star in every other one - a brass rim, the name in brass capitals, a brass emblem
// in a ring - and the movie palace's forecourt of concrete slabs pressed with hands, shoes and
// signatures. One material for both; which one a vertex is rides in UV2.y (0 the walk, 1 the
// forecourt). Everything is drawn per pixel from the mesh's UV (metres; never world positions,
// which an origin shift moves) and one lettering atlas (assets/textures/star_boulevard/
// walk_atlas.png, tools/make_star_boulevard_art.py: names, signatures, emblems).
//
// The walk: UV.x metres along the boulevard toward the reader's right as they face the buildings
// (true world, so squares line up block to block), UV.y metres in from the band's kerb-side edge
// (0 .. BAND); UV2.x a per-side salt. The forecourt: UV metres across the frontage and in from the
// street, UV2.x the palace's salt.
// Colour arithmetic in linear on both renderers (color_space.gdshaderinc).

render_mode depth_draw_opaque, cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D atlas : filter_linear_mipmap_anisotropic, repeat_disable;
// Which names the stars carry (a different city per seed).
uniform int seed_salt = 0;
// The number of names in the atlas (StarNames.NAMES.size()).
uniform int name_count = 120;
// Linear colours.
uniform vec3 charcoal = vec3(0.022, 0.022, 0.026);
uniform vec3 coral = vec3(0.50, 0.17, 0.14);
uniform vec3 coral_star = vec3(0.64, 0.24, 0.20);
uniform vec3 brass = vec3(0.66, 0.46, 0.20);
uniform vec3 concrete = vec3(0.40, 0.37, 0.33);
uniform float terrazzo_roughness = 0.26;
uniform float brass_roughness = 0.32;

global uniform float road_wetness;

const float BAND = 1.4;
const float EDGE = 0.2;
const float CELL = 1.0;
const float STRIP = 0.012;
const vec2 ATLAS_CELL = vec2(256.0 / 1024.0, 32.0 / 2048.0);
const float SIG_ROW0 = 32.0;
const float EMBLEM_Y = (2048.0 - 64.0) / 2048.0;
const vec2 EMBLEM_SIZE = vec2(64.0 / 1024.0, 64.0 / 2048.0);

uint lowbias32(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

uint h3(int a, int b, int c) {
	return lowbias32(uint(a) * 0x9E3779B9u ^ lowbias32(uint(b) + 0x632BE5ABu) ^ lowbias32(uint(c) * 0x85EBCA6Bu + 17u));
}

float h01(int a, int b, int c) {
	return float(h3(a, b, c) & 0xFFFFu) / 65535.0;
}

// Terrazzo: marble chips in a cement matrix, a few millimetres to a couple of centimetres, as a
// cellular field (the nearest of four jittered chips per 2.2 cm cell). Returns the chip's tone
// change and whether we are on one.
vec2 terrazzo(vec2 p, int salt) {
	vec2 g = p / 0.022;
	vec2 i = floor(g);
	vec2 f = g - i;
	float best = 9.0;
	float tone = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 c = ivec2(i) + ivec2(x, y);
			uint h = h3(c.x, c.y, salt);
			vec2 o = vec2(float(h & 255u), float((h >> 8u) & 255u)) / 255.0;
			float r = 0.25 + 0.3 * float((h >> 16u) & 255u) / 255.0;
			float d = length(vec2(float(x), float(y)) + o - f) / r;
			if (d < best) {
				best = d;
				float k = float((h >> 24u) & 255u) / 255.0;
				// Mostly pale marble, some grey, a few black and a few warm chips.
				tone = k < 0.55 ? 0.55 : (k < 0.8 ? 0.2 : (k < 0.92 ? -0.6 : 0.85));
			}
		}
	}
	float on = 1.0 - smoothstep(0.8, 1.0, best);
	return vec2(tone, on);
}

// A five-pointed star's signed distance (iq), outer radius r, inner ratio from rf.
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
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

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// A hand pressed into the concrete, palm at the origin, fingers toward +y, `s` its size (~1).
float sd_hand(vec2 p, float s, float spread) {
	p /= s;
	float d = length((p - vec2(0.0, -0.01)) / vec2(0.048, 0.058)) - 1.0;
	d *= 0.048;
	// Four fingers fanned a little, then the thumb out to the side.
	float base_y = 0.045;
	for (int i = 0; i < 4; i++) {
		float fi = float(i) - 1.5;
		float a = fi * 0.12 * spread;
		float len = (i == 0 || i == 3) ? 0.062 : 0.078;
		if (i == 3) len = 0.052;
		vec2 b0 = vec2(fi * 0.024, base_y);
		vec2 dir = vec2(sin(a), cos(a));
		d = min(d, sd_capsule(p, b0, b0 + dir * len, 0.0105));
	}
	d = min(d, sd_capsule(p, vec2(0.040, -0.010), vec2(0.082, 0.032), 0.0125));
	return d * s;
}

// A shoe print: sole and heel, toe toward +y.
float sd_shoe(vec2 p, float s) {
	p /= s;
	float sole = length((p - vec2(0.0, 0.05)) / vec2(0.045, 0.075)) - 1.0;
	float heel = length((p - vec2(0.0, -0.085)) / vec2(0.035, 0.04)) - 1.0;
	return min(sole * 0.045, heel * 0.035) * s;
}

float ink(vec2 uv) {
	return texture(atlas, uv).r;
}

// A name cell's ink at local (0..1, 0..1) of cell k in rows starting at row0.
float name_ink(int k, float row0, vec2 l) {
	if (l.x < 0.0 || l.x > 1.0 || l.y < 0.0 || l.y > 1.0) return 0.0;
	vec2 cell = vec2(float(k % 4), row0 + float(k / 4));
	// The atlas's y runs down; the cell's local y runs up.
	return ink((cell + vec2(l.x, 1.0 - l.y)) * ATLAS_CELL);
}

float emblem_ink(int e, vec2 l) {
	if (l.x < 0.0 || l.x > 1.0 || l.y < 0.0 || l.y > 1.0) return 0.0;
	return ink(vec2(float(e) * EMBLEM_SIZE.x + l.x * EMBLEM_SIZE.x, EMBLEM_Y + (1.0 - l.y) * EMBLEM_SIZE.y));
}

void fragment() {
	vec2 p = UV;
	float px = max(length(fwidth(p)), 1e-4);
	int salt = int(UV2.x + 0.5) + seed_salt * 7;
	vec3 col;
	float rough = terrazzo_roughness;
	float metal = 0.0;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	if (UV2.y < 0.5) {
		// --- The walk ---
		int n = int(floor(p.x / CELL));
		float lx = p.x / CELL - float(n);
		float ly = (p.y - EDGE) / CELL;
		bool in_sq = p.y > EDGE && p.y < EDGE + CELL;
		vec2 tz = terrazzo(p, salt);
		vec3 base = in_sq ? charcoal : coral;
		// The chips: lighter in charcoal, the coral's own palette in the borders.
		vec3 chip = in_sq ? mix(vec3(0.55, 0.54, 0.52), vec3(0.008), step(tz.x, 0.0)) : mix(vec3(0.85, 0.62, 0.55), vec3(0.20, 0.06, 0.05), step(tz.x, 0.0));
		col = mix(base, chip * (0.6 + 0.4 * abs(tz.x)), tz.y * (in_sq ? 0.42 : 0.35));
		// Brass divider strips: between the squares and down both edges of the square row.
		float sx = min(lx, 1.0 - lx) * CELL;
		float sy = min(abs(p.y - EDGE), abs(p.y - EDGE - CELL));
		float strip = 1.0 - smoothstep(STRIP * 0.5 - px * 0.5, STRIP * 0.5 + px * 0.5, in_sq ? min(sx, sy) : sy);
		// Every other square carries a star.
		if (in_sq && (n & 1) == 0) {
			vec2 q = vec2(lx, ly) - vec2(0.5, 0.5);
			float d = sd_star5(q, 0.45, 0.47);
			float star = 1.0 - smoothstep(-px * 0.5, px * 0.5, d);
			vec2 tz2 = terrazzo(p * 1.3 + 7.0, salt + 3);
			vec3 sc = mix(coral_star, vec3(0.92, 0.70, 0.62), tz2.y * step(0.0, tz2.x) * 0.45);
			sc = mix(sc, vec3(0.16, 0.05, 0.04), tz2.y * step(tz2.x, 0.0) * 0.4);
			col = mix(col, sc, star);
			float rim = 1.0 - smoothstep(STRIP * 0.5 - px * 0.5, STRIP * 0.5 + px * 0.5, abs(d));
			strip = max(strip, rim);
			// The name across the upper star, the emblem in its ring under it.
			int k = int(h3(n, salt, 11) % uint(max(name_count, 1)));
			float nm = name_ink(k, 0.0, (q - vec2(-0.29, 0.085)) / vec2(0.58, 0.0725));
			int e = int(h3(n, salt, 23) % 5u);
			vec2 ec = q - vec2(0.0, -0.075);
			float er = length(ec);
			float ring = 1.0 - smoothstep(0.0055 - px * 0.5, 0.0055 + px * 0.5, abs(er - 0.088));
			float disc = 1.0 - smoothstep(0.088 - px * 0.5, 0.088 + px * 0.5, er);
			float em = emblem_ink(e, ec / 0.16 + 0.5) * disc;
			col = mix(col, charcoal * 1.6, disc * 0.85);
			strip = max(strip, max(ring, max(smoothstep(0.35, 0.65, nm), smoothstep(0.35, 0.65, em))));
		}
		// Brass: polished where feet go, darker and duller in the corners of the strokes.
		float wear = h01(n, salt, 5);
		vec3 b = brass * (0.85 + 0.3 * wear);
		col = mix(col, b, strip);
		metal = strip * 0.9;
		rough = mix(rough, brass_roughness, strip);
		// A faint scuffed path down the middle of the band.
		float scuff = exp(-pow((p.y - BAND * 0.5) / 0.45, 2.0));
		rough = mix(rough, rough + 0.12, scuff * 0.5);
	} else {
		// --- The forecourt ---
		const float SLAB = 1.25;
		ivec2 c = ivec2(floor(p / SLAB));
		vec2 l = p / SLAB - vec2(c);
		uint h = h3(c.x, c.y, salt + 101);
		float tone = float(h & 255u) / 255.0;
		col = concrete * (0.82 + 0.3 * tone);
		col = mix(col, vec3(0.46, 0.40, 0.33), 0.25 * float((h >> 8u) & 1u));
		vec2 tz = terrazzo(p * 0.5, salt + 9);
		col *= 1.0 - tz.y * 0.08 * (0.5 + tz.x);
		rough = 0.82;
		// Grout joints between the slabs.
		float jx = min(l.x, 1.0 - l.x) * SLAB;
		float jy = min(l.y, 1.0 - l.y) * SLAB;
		float joint = 1.0 - smoothstep(0.012 - px, 0.012 + px, min(jx, jy));
		// Three slabs in four are pressed; the frame of the slab is a tooled margin.
		float depth = 0.0;
		if (((h >> 9u) & 3u) != 0u && min(jx, jy) > 0.05) {
			vec2 q = (l - vec2(0.5)) * SLAB;
			float spread = 0.8 + 0.5 * float((h >> 12u) & 15u) / 15.0;
			float hs = 0.92 + 0.16 * float((h >> 16u) & 15u) / 15.0;
			float dl = sd_hand(vec2(-(q.x + 0.21), q.y - 0.12) * vec2(1.0, 1.0), hs, spread);
			float dr = sd_hand(q - vec2(0.21, 0.12), hs, spread);
			float dh = min(dl, dr);
			if (((h >> 20u) & 1u) == 1u) {
				dh = min(dh, sd_shoe(q - vec2(-0.13, -0.33), 1.05));
				dh = min(dh, sd_shoe(q - vec2(0.13, -0.33), 1.05));
			}
			float press = 1.0 - smoothstep(-px, px, dh);
			depth = press;
			// The signature and the year, written with a stick in the wet concrete.
			int k = int(h3(c.x, c.y, salt + 77) % uint(max(name_count, 1)));
			float sg = name_ink(k, SIG_ROW0, (q - vec2(-0.40, -0.14)) / vec2(0.80, 0.10));
			depth = max(depth, smoothstep(0.3, 0.7, sg) * 0.7);
			// Inside an impression: darker (grime collects), a little smoother.
			// The impression's wall, as a normal from the distance's gradient.
			vec2 g = vec2(dFdx(dh), dFdy(dh));
			float wall = (1.0 - smoothstep(0.0, 0.006, abs(dh))) ;
			nrm = normalize(vec3(-g / max(length(g), 1e-6) * wall * 0.45, 1.0));
		}
		col *= 1.0 - depth * 0.38;
		rough = mix(rough, 0.72, depth);
		col = mix(col, col * 0.62, joint);
	}
	// Wet: darker, glossier (the road's global).
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= 1.0 - wet * 0.35;
	rough = mix(rough, 0.08, wet * 0.85);
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	NORMAL_MAP = nrm * 0.5 + 0.5;
}
