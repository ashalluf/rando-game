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
uniform float sign_night = 2.4;
// The ceiling's light panels and the coolers' lit backs (always on: the store is open).
uniform float troffer_energy = 3.2;
uniform float cooler_energy = 1.9;

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
		NORMAL_MAP = texture(plaster_nrm, uv / 2.4).rgb;
		NORMAL_MAP_DEPTH = 0.7;
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
		float seam = grid_line(uv.x, 0.305, 0.004) + grid_line(uv.y, 0.305, 0.004);
		base *= 1.0 - 0.25 * clamp(seam, 0.0, 1.0);
		// Waxed, worn dull down the aisles' middles.
		float wear = noise2(uv * 0.7);
		rough = mix(0.22, 0.5, wear);
	} else if (kind == K_CEILING) {
		float bars = max(grid_line(uv.x, 0.61, 0.024), grid_line(uv.y, 1.22, 0.024));
		float speck = noise2(uv * 60.0);
		base *= mix(0.9 + 0.1 * speck, 0.82, bars);
		rough = 0.95;
	} else if (kind == K_TROFFER) {
		// A lens of small square cells in a white frame.
		float cell = max(grid_line(uv.x, 0.06, 0.006), grid_line(uv.y, 0.06, 0.006));
		vec3 lightc = vec3(1.0, 0.97, 0.91);
		emit = lightc * troffer_energy * (1.0 - 0.35 * cell);
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
		base *= 0.55;
		rough = 0.25;
	} else if (kind == K_LETTERS) {
		emit = base * (sign_day * 1.6 + sign_night * 1.3 * lamp);
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
