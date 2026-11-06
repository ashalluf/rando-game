shader_type spatial;
// A wheelie bin (KerbBins.mesh()): moulded HDPE in the cart's colour (the MultiMesh instance colour,
// raw sRGB numbers on both renderers), a slightly glossier lid, rubber wheels, a steel axle, a
// printed label. What a face is rides in the vertex alpha (1 body, 0.8 lid, 0.6 rubber,
// 0.4 steel, 0.2 label). Works in linear (color_space.gdshaderinc).
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

// A cart carried by a garbage truck's arm is a plain mesh: its colour comes from here instead.
uniform bool use_fixed = false;
uniform vec3 fixed_tint = vec3(0.1);

varying float kind;
varying vec3 tint;
varying vec3 local_pos;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	kind = COLOR.a;
	tint = use_fixed ? fixed_tint : COLOR.rgb;
	local_pos = VERTEX;
}

void fragment() {
	vec3 plastic = cs_srgb_to_linear(tint);
	// Each cart a little faded or newer than the next, from where it stands.
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float age = hash31(floor(wp * 0.7 + 0.5));
	plastic *= mix(0.85, 1.12, age);
	vec3 col = plastic;
	float rough = 0.62;
	float spec = 0.45;
	if (kind > 0.9) {
		// The body: a fine moulded grain, sun-chalking on the upper half, grime and scuffs low down.
		float grain = vnoise(local_pos * 140.0) * 0.5 + vnoise(local_pos * 31.0) * 0.5;
		col *= mix(0.92, 1.05, grain);
		float chalk = smoothstep(0.4, 1.0, local_pos.y) * (0.06 + 0.10 * age);
		col = mix(col, vec3(0.45), chalk);
		float grime = (1.0 - smoothstep(0.0, 0.35, local_pos.y)) * (0.35 + 0.4 * vnoise(local_pos * 9.0));
		col *= 1.0 - grime * 0.45;
		float scuff = step(0.82, vnoise(local_pos * vec3(5.0, 40.0, 5.0)));
		col = mix(col, col * 1.35 + 0.02, scuff * 0.5);
		rough = mix(0.55, 0.75, grain) + chalk;
	} else if (kind > 0.7) {
		col *= 0.95;
		rough = 0.48 + 0.15 * vnoise(local_pos * 60.0);
		col = mix(col, vec3(0.30), smoothstep(0.8, 1.1, local_pos.y) * 0.08);
	} else if (kind > 0.5) {
		col = vec3(0.022, 0.022, 0.024);
		rough = 0.85;
		spec = 0.3;
	} else if (kind > 0.3) {
		col = vec3(0.30, 0.30, 0.31);
		rough = 0.45;
	} else {
		// A label: white, a coloured band across its top, lines of print (no words).
		vec2 l = vec2(local_pos.z, local_pos.y);
		float top = smoothstep(0.0, 0.004, l.y - 0.62);
		col = mix(vec3(0.80, 0.80, 0.76), plastic * 0.5 + vec3(0.02, 0.04, 0.10), top);
		float lines = step(0.55, fract(l.y * 55.0)) * step(-0.09, l.x) * step(l.x, 0.06) * (1.0 - top);
		col = mix(col, vec3(0.08), lines * 0.6);
		rough = 0.7;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	SPECULAR = spec;
}
