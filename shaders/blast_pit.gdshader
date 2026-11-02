shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The crater's pit with depth (Blast4, fleet wave 5 "explosions-4", round 6). The road cannot be
// cut, so the bowl is TRACED: a quad laid just over the road, and each pixel follows its view ray
// down into a height field (a dish `depth` deep at the middle, `pit_r` across, its floor heaped
// with rubble lumps from the tiling noise) until it meets it, and shades what it hits: scorched
// earth and crushed base course, darker and sootier deeper in, broken asphalt in at the edge, lit
// by the renderer through the field's own normal. Outside the opening the quad is transparent.
// Colours linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform float pit_r = 2.0;
uniform float depth = 0.8;
uniform float quad_r = 2.2;
uniform float seed = 0.0;
uniform vec3 soil = vec3(0.032, 0.026, 0.02);
uniform vec3 soot = vec3(0.006, 0.0055, 0.005);
uniform vec3 base_course = vec3(0.075, 0.066, 0.055);

varying vec3 v_local;
varying vec3 v_cam_local;

void vertex() {
	v_local = VERTEX;
	v_cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

float lumps(vec2 p) {
	float a = texture(noise3d, vec3(p * 0.42 + seed, 0.31)).r;
	float b = texture(noise3d, vec3(p * 1.3 + seed * 1.7, 0.67)).r;
	// Rubble: sharpened lumps, big and small.
	return smoothstep(0.35, 0.75, a) * 0.6 + smoothstep(0.45, 0.8, b) * 0.4;
}

// Height of the pit's floor at p (metres, 0 = road level, negative down).
float field(vec2 p) {
	float s = length(p) / pit_r;
	float dish = -depth * max(1.0 - s * s, 0.0);
	// A heap of rubble in the bottom, lumps up the sides.
	float heap = lumps(p) * depth * 0.35 * (1.0 - smoothstep(0.55, 1.0, s));
	return dish + heap;
}

void fragment() {
	vec3 p0 = v_local;
	float r0 = length(p0.xz);
	if (r0 > pit_r * 1.02) {
		discard;
	}
	vec3 dir = normalize(p0 - v_cam_local);
	// From the opening down along the ray until it is under the field.
	float dy = min(dir.y, -0.08);
	float len = (depth * 1.1) / -dy;
	const int N = 28;
	vec3 prev = p0;
	vec3 hit = p0 + dir * len;
	float prev_d = p0.y - field(p0.xz);
	for (int i = 1; i <= N; i++) {
		vec3 q = p0 + dir * (len * float(i) / float(N));
		float d = q.y - field(q.xz);
		if (d < 0.0) {
			float k = prev_d / max(prev_d - d, 1e-4);
			hit = mix(prev, q, k);
			break;
		}
		prev = q;
		prev_d = d;
	}
	vec2 h = hit.xz;
	float e = 0.04;
	vec3 n = normalize(vec3(field(h - vec2(e, 0.0)) - field(h + vec2(e, 0.0)), 2.0 * e, field(h - vec2(0.0, e)) - field(h + vec2(0.0, e))));
	float s = length(h) / pit_r;
	float down = clamp(-hit.y / max(depth, 0.01), 0.0, 1.0);
	float lp = lumps(h);
	vec3 col = mix(base_course, soil, smoothstep(0.55, 0.85, 1.0 - s) * 0.6 + 0.4 * lp);
	col = mix(col, soot, clamp(down * 1.1 + (1.0 - lp) * 0.3, 0.0, 0.92));
	// Broken asphalt where the opening meets the road.
	col = mix(col, vec3(0.02, 0.019, 0.018), smoothstep(0.82, 0.97, s) * 0.8);
	// Shade deep in: the walls hide it from the sky.
	float ao = mix(0.85, 0.22, pow(down, 0.7));
	ALBEDO = cs_out(col * ao);
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	ALPHA = 1.0 - smoothstep(0.94, 1.02, r0 / pit_r);
}
