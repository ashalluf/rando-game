shader_type spatial;
// The street performers' gear (Buskers): guitars, a guitarron, a violin and its bow, a trumpet,
// drum buckets, sticks, a cymbal, guitar cases with the tips in them, a boombox, a cardboard
// dance floor, a statue's plinth, a sombrero. Built in code at real size (Buskers.Kit); one
// shader for all of it, one draw per kind per chunk (or one per instrument a performer holds).
// COLOR.rgb is the paint, written as sRGB (vertex colours arrive raw on both renderers);
// COLOR.a is what the surface is, in tenths (Buskers.A_*). Works in linear (color_space).
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

varying float v_kind;
varying vec3 v_obj;
varying vec3 v_colour;

float bk_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bk_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bk_hash(i), bk_hash(i + vec2(1.0, 0.0)), f.x), mix(bk_hash(i + vec2(0.0, 1.0)), bk_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_kind = COLOR.a;
	v_obj = VERTEX;
	v_colour = COLOR.rgb;
}

void fragment() {
	int k = int(round(v_kind * 10.0));
	vec3 c = cs_srgb_to_linear(v_colour);
	float rough = 0.7;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	if (k == 1) {
		// Varnished wood: the grain runs along the instrument (mesh +X), figured by slow noise,
		// a clear lacquer over it.
		float g = bk_noise(vec2(v_obj.x * 3.0, (v_obj.y + v_obj.z) * 90.0 + bk_noise(v_obj.xy * 8.0) * 6.0));
		c *= mix(0.78, 1.12, g);
		rough = 0.22;
	} else if (k == 2) {
		metal = 1.0;
		rough = 0.26 + 0.12 * bk_noise(v_obj.xz * 40.0);
	} else if (k == 3) {
		metal = 1.0;
		rough = 0.18;
	} else if (k == 4) {
		// Moulded plastic (the buckets): satin, scuffed.
		rough = 0.42 + 0.25 * bk_noise(v_obj.xy * 23.0 + v_obj.z * 9.0);
		c *= mix(0.86, 1.0, bk_noise(v_obj.zy * 31.0));
	} else if (k == 5) {
		// Plush lining: very rough, a little lighter at grazing (the pile).
		rough = 0.98;
		c *= mix(0.85, 1.05, bk_noise(v_obj.xz * 140.0));
	} else if (k == 6) {
		// Cardboard: fluting shows through as faint stripes, scuffed toward the middle.
		float flute = 0.5 + 0.5 * sin(v_obj.x * 1100.0);
		float scuff = bk_noise(v_obj.xz * 3.0);
		c *= mix(0.9, 1.04, flute) * mix(0.72, 1.0, smoothstep(0.25, 0.75, scuff));
		rough = 0.92;
	} else if (k == 7) {
		// Silver paint (a statue's box): metallic flake, brushed on.
		metal = 0.75;
		rough = 0.42 + 0.12 * bk_noise(vec2(v_obj.y * 60.0, v_obj.x * 4.0));
	} else if (k == 8) {
		rough = 0.82;
	} else if (k == 9) {
		// A sound hole or a bell's throat: dark inside.
		c *= 0.08;
		rough = 0.9;
	} else if (k == 10) {
		// A boombox display: green segments, brighter at night.
		glow = c * mix(0.6, 2.2, lamp_factor);
		rough = 0.3;
	}
	// Wet pavement props darken a little.
	if (k == 6 || k == 5) {
		c *= 1.0 - 0.35 * road_wetness;
	}
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(glow);
}
