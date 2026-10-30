shader_type spatial;
render_mode cull_back;

// The beach's public amenities (scripts/world/beach_amenities.gd): restroom blocks, the
// concession and rental stand, the outdoor gym pen, showers, bike racks, the extra volleyball
// poles and the painted drums on the sand. One material for all of it, so each kind is one
// MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is: round(alpha * 32) = BeachAmenities.K_* (1 concrete,
//   2 split-face block, 3 the instance's paint, 4 galvanised steel, 5 stainless, 6 timber,
//   7 striped canvas, 8 a lamp, 9 a painted sign, 10 rubber, 11 dark glass, 12 the menu board,
//   13 a shower pad, 14 chain, 15 a roll-up shutter, 16 sand-blasted wood (the gym's border)).
//   The rgb is the colour (sRGB) for every kind but 3.
// * UV is metres in the face's plane (StreetClutter._proj); UV2 is (roughness, metallic).
// * INSTANCE_CUSTOM: rgb a paint (sRGB; drums, gym frames), a a seed 0..1. The instance COLOR
//   stays white (it multiplies every vertex colour).
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// The sand's colour (sRGB) where it drifts against the foot of a wall and dusts low steel.
uniform vec3 sand_tint = vec3(0.80, 0.71, 0.56);
// Split-face block coursing (m).
uniform vec2 block_size = vec2(0.406, 0.203);
// How bright a lit lamp face is (HDR, x lamp_factor).
uniform float lamp_energy = 5.0;

varying vec3 v_local;
varying float v_code;
varying vec3 v_paint;
varying float v_seed;
varying vec3 v_world;

float ba_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float ba_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ba_hash(i), ba_hash(i + vec2(1.0, 0.0)), f.x),
		mix(ba_hash(i + vec2(0.0, 1.0)), ba_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ba_fbm(vec2 p) {
	return 0.5 * ba_noise(p) + 0.3 * ba_noise(p * 2.13 + 7.1) + 0.2 * ba_noise(p * 4.37 + 3.3);
}

void vertex() {
	v_local = VERTEX;
	v_code = COLOR.a;
	v_paint = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int code = int(round(v_code * 32.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 sand = cs_srgb_to_linear(sand_tint);
	vec3 emit = vec3(0.0);
	vec2 uv = UV;
	// A pixel's footprint in metres: detail under it is faded to its average.
	float px = max(length(fwidth(uv)), 1e-4);
	float seed = v_seed * 37.0;
	// How much the sea air, sun and sand have had at it.
	float grime = ba_fbm(uv * 1.7 + seed);
	if (code == 1) {
		// Cast concrete: form-tie holes and pour lines, mottle, salt bloom.
		base *= 0.88 + 0.16 * ba_fbm(uv * 2.3 + seed) + 0.05 * mix(ba_noise(uv * 31.0), 0.5, smoothstep(0.01, 0.05, px));
		float pour = 1.0 - smoothstep(0.004, 0.01 + px, abs(fract(uv.y / 1.22) - 0.5) * 1.22 - 0.6);
		base *= 1.0 - 0.06 * pour * (1.0 - smoothstep(0.05, 0.2, px));
		rough = 0.9;
	} else if (code == 2) {
		// Split-face block: staggered courses, each block its own shade and a rough face; the
		// mortar joints recessed and darker.
		vec2 b = uv / block_size;
		float row = floor(b.y);
		b.x += 0.5 * mod(row, 2.0);
		vec2 cell = floor(b);
		vec2 f = fract(b);
		vec2 d = min(f, 1.0 - f) * block_size;
		float joint = 1.0 - smoothstep(0.006, 0.012 + px, min(d.x, d.y));
		joint *= 1.0 - smoothstep(0.03, 0.1, px);
		float shade = 0.9 + 0.18 * ba_hash(cell + seed);
		float face = ba_noise(uv * 26.0 + cell * 3.1);
		base *= shade * (0.9 + 0.2 * mix(face, 0.5, smoothstep(0.01, 0.05, px)));
		base = mix(base, base * 0.62, joint);
		NORMAL_MAP = normalize(vec3(0.5 + (face - 0.5) * 0.35 * (1.0 - smoothstep(0.01, 0.05, px)), 0.5, 1.0));
		rough = 0.93;
	} else if (code == 3) {
		// The instance's paint, chalky and chipped: rust where it is chipped.
		vec3 paint = cs_srgb_to_linear(v_paint);
		float chip = smoothstep(0.66, 0.72, ba_fbm(uv * 5.0 + seed * 3.0)) * (1.0 - smoothstep(0.02, 0.08, px) * 0.6);
		base = mix(paint * (0.92 + 0.1 * ba_noise(uv * 11.0 + seed)), cs_srgb_to_linear(vec3(0.42, 0.24, 0.14)), chip * 0.8);
		// Faded on what faces the sky.
		float sky = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
		base = mix(base, vec3(dot(base, vec3(0.333))) * 1.1, 0.2 * sky);
		rough = mix(0.62, 0.85, chip);
		metal = 0.0;
	} else if (code == 4) {
		// Galvanised steel: spangle, white rust bloom low down.
		float spangle = ba_noise(uv * 18.0 + seed);
		base *= 0.85 + 0.25 * mix(spangle, 0.5, smoothstep(0.01, 0.06, px));
		base = mix(base, cs_srgb_to_linear(vec3(0.78, 0.78, 0.74)), 0.25 * smoothstep(0.55, 0.8, grime));
		rough = 0.42 + 0.25 * spangle;
		metal = 0.75;
	} else if (code == 5) {
		// Brushed stainless: the grain runs along the face's long way, water spots.
		float brush = ba_noise(vec2(uv.x * 2.0, uv.y * 140.0));
		base *= 0.92 + 0.12 * mix(brush, 0.5, smoothstep(0.004, 0.02, px));
		float spot = smoothstep(0.72, 0.8, ba_noise(uv * 30.0 + seed));
		rough = 0.22 + 0.12 * brush + 0.25 * spot;
		metal = 0.95;
	} else if (code == 6 || code == 16) {
		// Timber: grain along u, boards, checks; the gym's border sandblasted silver.
		float g = ba_noise(vec2(uv.x * 1.2, uv.y * 38.0) + seed);
		float rings = abs(fract(uv.y * 9.0 + g * 1.6) - 0.5);
		base *= 0.82 + 0.25 * g + 0.08 * mix(rings, 0.25, smoothstep(0.01, 0.04, px));
		if (code == 16) {
			base = mix(base, vec3(dot(base, vec3(0.3, 0.45, 0.25))) * 1.15, 0.6);
		}
		rough = 0.88;
	} else if (code == 7) {
		// Striped awning canvas: the vertex colour and the instance's paint across u.
		float fw = max(fwidth(uv.x) * 2.0, 1e-4);
		float s = smoothstep(0.5 - fw, 0.5 + fw, abs(fract(uv.x / 0.6) - 0.5) * 2.0);
		base = mix(base, cs_srgb_to_linear(v_paint), s);
		base *= 0.94 + 0.08 * ba_noise(uv * 90.0);
		base = mix(base, vec3(dot(base, vec3(0.333))), 0.12);
		rough = 0.85;
		BACKLIGHT = cs_out(base * 0.4);
	} else if (code == 8) {
		// A lamp: a frosted lens, lit after dark.
		rough = 0.3;
		emit = base * lamp_energy * lamp_factor;
	} else if (code == 9) {
		// A painted sign: weathered a little.
		base *= 0.93 + 0.1 * ba_noise(uv * 7.0 + seed);
		rough = 0.55;
	} else if (code == 10) {
		base *= 0.85 + 0.2 * ba_noise(uv * 40.0);
		rough = 0.92;
	} else if (code == 11) {
		rough = 0.08;
		metal = 0.0;
	} else if (code == 12) {
		// The menu board: rows of hand-lettered items on a dark board, lit after dark.
		vec2 g = uv * vec2(1.0, 1.0);
		float row = fract(g.y / 0.11);
		float line = step(0.32, row) * step(row, 0.62);
		float word = step(0.38, ba_noise(vec2(floor(g.x / 0.05), floor(g.y / 0.11)) * 0.9 + seed));
		float price = step(0.82, fract(g.x / 0.9 + 0.02));
		float ink = line * max(word, price) * (1.0 - smoothstep(0.005, 0.02, px));
		ink = max(ink, line * 0.45 * smoothstep(0.005, 0.02, px));
		vec3 chalk = cs_srgb_to_linear(mix(vec3(0.95, 0.93, 0.85), vec3(0.98, 0.78, 0.25), price));
		base = mix(base, chalk, ink);
		rough = 0.7;
		emit = base * 0.9 * lamp_factor;
	} else if (code == 13) {
		// A shower pad: wet concrete round the drain, a steel grate in the middle.
		float r = length(v_local.xz);
		float wet = 1.0 - smoothstep(0.5, 1.15 + 0.25 * ba_noise(v_local.xz * 3.0 + seed), r);
		base *= 0.88 + 0.14 * ba_fbm(uv * 2.0 + seed);
		vec2 g = abs(v_local.xz);
		float grate = step(max(g.x, g.y), 0.22);
		float slot = step(0.5, fract(v_local.x / 0.025));
		base = mix(base * mix(1.0, 0.55, wet), cs_srgb_to_linear(vec3(0.16, 0.16, 0.15)) * (0.6 + 0.4 * slot), grate);
		rough = mix(0.88, 0.12, max(wet, grate * 0.5));
	} else if (code == 14) {
		float link = abs(fract(uv.y / 0.035) - 0.5);
		base *= 0.75 + 0.35 * link;
		rough = 0.45;
		metal = 0.85;
	} else if (code == 15) {
		// A roll-up shutter: horizontal ribs, scuffed.
		float rib = abs(fract(uv.y / 0.075) - 0.5) * 2.0;
		base *= 0.78 + 0.25 * mix(rib, 0.5, smoothstep(0.01, 0.04, px));
		base = mix(base, base * 0.7, 0.3 * smoothstep(0.6, 0.85, grime));
		rough = 0.5;
		metal = 0.6;
	}
	// Sand drifted against the foot of things, and dusted on low steel and concrete.
	if (code != 8 && code != 11 && code != 12) {
		float low = 1.0 - smoothstep(0.0, 0.45 + 0.35 * ba_noise(uv * 1.3 + seed), v_local.y);
		float dust = low * (0.35 + 0.65 * ba_noise(uv * 6.0 + seed * 2.0));
		base = mix(base, sand, clamp(dust * 0.75, 0.0, 0.85));
		rough = mix(rough, 0.95, dust * 0.7);
		metal *= 1.0 - dust * 0.6;
	}
	// Rain darkens and glosses what faces the sky.
	if (road_wetness > 0.01 && code != 8) {
		float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) * 0.6 + 0.4, 0.0, 1.0);
		base *= 1.0 - 0.3 * road_wetness * up;
		rough = mix(rough, 0.15, road_wetness * up * 0.7);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
