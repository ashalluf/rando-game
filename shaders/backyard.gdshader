shader_type spatial;
render_mode cull_back;

// Backyard life (Backyards / BackyardKit, scripts/world/backyards.gd and backyard_kit.gd): patio
// furniture, umbrellas, grills, trampolines, pool floats, laundry, citrus fruit, doghouses, toys
// and the string lights over a patio, all on this one shader so each kind is one MultiMesh draw a
// chunk (and a chunk's string lights one mesh).
//
// Vertex data (written by BackyardKit):
//   COLOR.rgb  an sRGB colour (K_FIXED, K_METAL, K_WOOD, K_STEEL ...) or a shade multiplying the
//              instance's paint (K_PAINT, K_GLOSS, K_FRUIT, K_VINYL)
//   COLOR.a    what the face is: floor(a * 16), BackyardKit.K_*
//   UV         metres along the face (weave, grain, mat)
//   UV2.x      a part id: the umbrella panel (stripes), the garment (laundry), the band (floats)
//   UV2.y      how free the vertex is to move in the wind (laundry)
//   CUSTOM0    a string-light bulb's centre (xyz) and 1 in w; 0 elsewhere
//   INSTANCE_CUSTOM  rgb the paint (sRGB), a the fabric palette (index / 8 for fabric and canvas,
//              +0.5 for striped canvas) or the household's seed (laundry, the grill's cooking)
// Colours: vertex and instance colours arrive raw on both renderers, so they are decoded from
// sRGB here, the arithmetic runs in linear and color_space.gdshaderinc hands the result over.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float city_hour;
global uniform float wind_factor;
global uniform float road_wetness;

/// The floats' material sets this: the whole instance bobs and turns on the water.
uniform float bob = 0.0;
/// How bright a string-light bulb is after dark (linear emission) and its colour.
uniform float bulb_energy = 6.0;
uniform vec3 bulb_color = vec3(1.0, 0.62, 0.28);
/// A bulb is never drawn smaller than this many pixels across (from the air), its light spread.
uniform float bulb_min_px = 1.6;
/// A grill's fire through the gap and the share of grills cooking at dinner time.
uniform float ember_energy = 3.5;
uniform float cook_share = 0.55;
/// Laundry and valance sway (metres at the free end).
uniform float sway = 0.05;

varying flat int v_code;
varying vec3 v_paint;
varying float v_pal;
varying vec3 v_local;
varying float v_bulb_gain;
varying float v_seed;

// The outdoor fabric colours (sRGB): navy, sand, grey, terracotta, sage, charcoal, cream, teal.
const vec3 FABRIC[8] = vec3[8](vec3(0.15, 0.21, 0.35), vec3(0.74, 0.65, 0.50), vec3(0.56, 0.56, 0.54),
	vec3(0.66, 0.34, 0.23), vec3(0.50, 0.58, 0.46), vec3(0.20, 0.20, 0.21), vec3(0.88, 0.85, 0.77), vec3(0.16, 0.44, 0.47));
// Laundry: whites, blues, a red, greys, a yellow, pinks, black, khaki, denim.
const vec3 CLOTH[12] = vec3[12](vec3(0.92, 0.92, 0.9), vec3(0.86, 0.88, 0.9), vec3(0.32, 0.45, 0.66), vec3(0.72, 0.2, 0.18),
	vec3(0.55, 0.55, 0.55), vec3(0.93, 0.8, 0.36), vec3(0.88, 0.62, 0.66), vec3(0.12, 0.12, 0.13), vec3(0.66, 0.6, 0.46),
	vec3(0.25, 0.33, 0.48), vec3(0.6, 0.78, 0.84), vec3(0.95, 0.94, 0.88));

float by_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float by_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(by_hash(i), by_hash(i + vec2(1.0, 0.0)), f.x), mix(by_hash(i + vec2(0.0, 1.0)), by_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 1 while this grill is cooking (an evening window per household), 0 otherwise.
float cooking(float seed) {
	if (seed >= cook_share) {
		return 0.0;
	}
	float s = seed / max(cook_share, 0.001);
	float start = 17.1 + s * 1.2;
	float len = 1.5 + fract(s * 7.31) * 1.6;
	float h = city_hour;
	return smoothstep(start, start + 0.15, h) * (1.0 - smoothstep(start + len - 0.2, start + len, h));
}


void vertex() {
	v_code = int(floor(COLOR.a * 16.0));
	v_paint = INSTANCE_CUSTOM.rgb;
	v_pal = INSTANCE_CUSTOM.a;
	v_seed = INSTANCE_CUSTOM.a;
	v_bulb_gain = 1.0;
	vec3 inst = MODEL_MATRIX[3].xyz;
	if (bob > 0.5) {
		float ph = by_hash(floor(inst.xz * 3.0)) * 6.2832;
		float a = TIME * 0.05 + ph;
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		VERTEX.xz = r * VERTEX.xz;
		NORMAL.xz = r * NORMAL.xz;
		VERTEX.y += sin(TIME * 1.4 + ph) * 0.018 + VERTEX.x * sin(TIME * 1.1 + ph) * 0.03;
	}
	if (UV2.y > 0.001) {
		// Cloth in the wind: a slow swing and a quicker ripple, more in a Santa Ana.
		float w = sway * (0.6 + wind_factor * 1.6);
		float ph = dot(inst.xz, vec2(0.37, 0.61)) + UV2.x * 0.7;
		VERTEX.z += UV2.y * w * (sin(TIME * 1.6 + ph) + 0.35 * sin(TIME * 4.3 + ph * 2.0 + VERTEX.x * 3.0));
		VERTEX.x += UV2.y * w * 0.3 * sin(TIME * 1.2 + ph * 1.3);
	}
	if (CUSTOM0.w > 0.5) {
		// A string-light bulb: grown from its centre to stay about bulb_min_px wide from afar,
		// its light spread over the bigger dot. VIEWPORT_SIZE can read 0 in a vertex stage.
		vec3 cv = (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
		float vh = VIEWPORT_SIZE.y > 1.0 ? VIEWPORT_SIZE.y : 720.0;
		float px = max(-cv.z, 0.1) * 2.0 / (PROJECTION_MATRIX[1][1] * vh);
		float grow = clamp(bulb_min_px * px / 0.05, 1.0, 14.0);
		VERTEX = CUSTOM0.xyz + (VERTEX - CUSTOM0.xyz) * grow;
		v_bulb_gain = 1.0 / grow;
	}
	v_local = VERTEX;
}


void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	vec3 paint = cs_srgb_to_linear(v_paint);
	vec3 alb = base;
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float spec = 0.5;
	int code = v_code;
	if (code == 1 || code == 4 || code == 9 || code == 12) {
		alb = base * paint;
	}
	if (code == 1) {
		// Powder coat: satin, a fine orange-peel.
		rough = 0.48 + by_noise(UV * 60.0) * 0.08;
		metal = 0.15;
	} else if (code == 2) {
		// Outdoor fabric: the palette colour, a basket weave, a little fade on what faces up.
		int i = int(floor(fract(v_pal) * 8.0 + 0.001)) & 7;
		vec3 f = cs_srgb_to_linear(FABRIC[i]) * base;
		vec2 w = UV * 220.0;
		float weave = 0.9 + 0.1 * sin(w.x) * sin(w.y);
		alb = f * weave * mix(1.0, 1.12, clamp(up, 0.0, 1.0));
		rough = 0.88;
	} else if (code == 3) {
		rough = 0.42 + by_noise(UV * 8.0) * 0.18;
		metal = 0.85;
	} else if (code == 4) {
		rough = 0.24;
		spec = 0.55;
	} else if (code == 5) {
		// A bulb: frosted glass by day, lit after dark (lamp_factor), a slow flicker per bulb.
		alb = vec3(0.86, 0.84, 0.8);
		rough = 0.2;
		float flick = 0.94 + 0.06 * sin(TIME * 7.0 + UV2.x * 3.1);
		emit = bulb_color * bulb_energy * lamp_factor * v_bulb_gain * flick;
		alb *= 1.0 - 0.8 * lamp_factor;
	} else if (code == 6) {
		// The fire showing through: dark by day unless the grill cooks, glowing at dinner time.
		float on = cooking(v_seed);
		alb = vec3(0.03, 0.025, 0.02);
		float flick = 0.75 + 0.25 * by_noise(vec2(TIME * 3.0, v_local.x * 9.0 + v_seed * 40.0));
		emit = vec3(1.0, 0.32, 0.06) * ember_energy * on * flick * mix(0.4, 1.0, night_factor);
	} else if (code == 7) {
		// The jump mat: a black polypropylene weave, sheen along the threads.
		vec2 w = UV * 160.0;
		float weave = 0.75 + 0.25 * step(0.5, fract(w.x)) * step(0.5, fract(w.y));
		alb = base * weave;
		rough = 0.55;
		spec = 0.4;
	} else if (code == 8) {
		// Laundry: the garment's colour by household and piece, cotton.
		float h = by_hash(vec2(UV2.x * 1.37 + 3.0, v_seed * 91.7 + 1.0));
		int i = int(floor(h * 12.0)) % 12;
		alb = cs_srgb_to_linear(CLOTH[i]) * base;
		vec2 w = UV * 300.0;
		alb *= 0.92 + 0.08 * sin(w.x) * sin(w.y);
		rough = 0.92;
		BACKLIGHT = cs_out(alb * 0.35);
	} else if (code == 9) {
		// Peel: dimpled, glossy.
		float d = by_noise(v_local.xz * 180.0 + v_local.y * 90.0);
		alb *= 0.9 + 0.12 * d;
		rough = 0.32 + d * 0.15;
	} else if (code == 10) {
		// Timber: grain along u, a slow tone wander.
		float grain = by_noise(vec2(UV.x * 3.0, UV.y * 90.0 + UV.x * 2.0));
		alb = base * (0.82 + 0.3 * grain) * (0.9 + 0.2 * by_noise(UV * 2.0));
		rough = 0.75;
	} else if (code == 11) {
		// Umbrella canvas: palette colour, every other panel cream on a striped one, sun faded
		// toward the top, lit through from above (backlight).
		int i = int(floor(fract(v_pal) * 8.0 + 0.001)) & 7;
		vec3 f = cs_srgb_to_linear(FABRIC[i]);
		bool striped = v_pal >= 1.0;
		if (striped && int(UV2.x) % 2 == 1) {
			f = cs_srgb_to_linear(vec3(0.9, 0.87, 0.8));
		}
		vec2 w = UV * 180.0;
		alb = f * base * (0.92 + 0.08 * sin(w.x) * sin(w.y));
		rough = 0.9;
		BACKLIGHT = cs_out(alb * 0.45);
	} else if (code == 12) {
		// Vinyl: the paint, white bands, wet and shiny.
		if (UV2.x > 0.5) {
			alb = cs_srgb_to_linear(vec3(0.95, 0.95, 0.93));
		}
		rough = 0.12;
		spec = 0.6;
	} else if (code == 13) {
		rough = 0.85;
	} else if (code == 14) {
		// Brushed stainless: streaks along u.
		rough = 0.28 + by_noise(vec2(UV.x * 2.0, UV.y * 400.0)) * 0.16;
		metal = 0.95;
	} else if (code == 15) {
		alb = base * 0.4;
		rough = 0.05;
		spec = 0.7;
	}
	// A little garden grime low down on everything that stands on the ground.
	if (code != 5 && code != 6 && bob < 0.5) {
		float g = (1.0 - smoothstep(0.0, 0.25, v_local.y)) * (0.5 + 0.5 * by_noise(v_local.xz * 6.0));
		alb *= 1.0 - 0.18 * g;
	}
	// Rain wets what is out in it.
	rough = mix(rough, rough * 0.45, clamp(road_wetness, 0.0, 1.0) * clamp(up + 0.3, 0.0, 1.0));
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
