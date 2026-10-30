shader_type spatial;
render_mode cull_back;

// The steel of the city's billboards (Billboards' frame kit): trim, back sheet, stringers and
// bracing, catwalks, legs, monopole columns and heads, fixtures, the shelter lightbox's case.
// The colour is the vertex colour (sRGB, as written), the kind in its alpha (Billboards.Steel,
// (kind + 0.5) / 8): 0 painted steel, 1 a fixture's lens (lit after dark), 2 catwalk grating,
// 3 the back sheet, 4 galvanised steel and aluminium, 5 concrete. Weathering is in world space
// (no UVs). Colours in linear on both renderers (color_space.gdshaderinc). // comments only.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// A fixture's lens after dark (metal halide: a cool white).
uniform vec3 lens_color = vec3(1.0, 0.93, 0.8);
uniform float lens_energy = 6.0;

varying vec3 v_world;
varying vec3 v_obj;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_obj = VERTEX;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	int kind = int(floor(COLOR.a * 8.0));
	vec3 base = cs_in(COLOR.rgb);
	vec3 col = base;
	float rough = 0.6;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float px = max(fwidth(v_world.x), fwidth(v_world.z)) + fwidth(v_world.y);
	// Rust runs and dirt in world space, streaked down.
	float n1 = vnoise(vec2(v_world.x * 1.3 + v_world.z * 0.7, v_world.y * 0.25));
	float n2 = vnoise(v_world.xz * 3.1 + v_world.y * 2.3);
	if (kind == 0) {
		float rust = smoothstep(0.62, 0.9, n1) * (0.6 + 0.4 * n2);
		col = mix(base, vec3(0.16, 0.07, 0.03), rust * 0.6);
		col *= 0.9 + 0.2 * n2;
		rough = 0.62 + 0.25 * rust;
		metal = 0.15;
	} else if (kind == 1) {
		col = vec3(0.6, 0.6, 0.58);
		rough = 0.15;
		emit = lens_color * lens_energy * lamp_factor;
	} else if (kind == 2) {
		// Bar grating: slots along the walkway, dark between, faded to the mean under a pixel.
		float s = fract((v_obj.x + v_obj.z) / 0.035);
		float slot = smoothstep(0.35, 0.45, s) * (1.0 - smoothstep(0.75, 0.85, s));
		col = base * mix(1.0 - 0.75 * slot, 0.6, smoothstep(0.01, 0.03, px));
		rough = 0.7;
		metal = 0.3;
	} else if (kind == 3) {
		// The back sheet: dull paint with run-off from the top and panel lines every 1.2 m.
		float pl = fract(v_obj.x / 1.22);
		col = base * (0.88 + 0.14 * n2) * (1.0 - 0.25 * (1.0 - smoothstep(0.0, max(0.008, px * 0.5), min(pl, 1.0 - pl) * 1.22)));
		rough = 0.8;
	} else if (kind == 4) {
		col = base * (0.85 + 0.25 * n2);
		rough = 0.42 + 0.2 * n1;
		metal = 0.7;
	} else {
		col = base * (0.85 + 0.2 * n2);
		rough = 0.9;
	}
	col *= 1.0 - 0.15 * road_wetness;
	ALBEDO = cs_out(col);
	EMISSION = cs_out(emit);
	ROUGHNESS = rough;
	METALLIC = metal;
}
