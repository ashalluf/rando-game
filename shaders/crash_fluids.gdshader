shader_type spatial;
// What a crashed car leaks onto the road (CrashAftermath, scripts/vehicles/crash_aftermath.gd):
// one flat quad under its nose, the shape worked out here from three numbers. A small black pool
// of engine oil under the sump with a faint rainbow at its rim, a wider sheet of green coolant
// round it that has run a tongue down the slope (`flow`, the quad's own frame), and a ring of
// damp road round both. Grows with `spread` (0..1, pushed a few times a second while it spreads).
// Glossy (it is a liquid), alpha-blended over whatever it lies on, no depth write, no shadow.
// Linear on both renderers (color_space.gdshaderinc).
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://shaders/color_space.gdshaderinc"

uniform float spread = 1.0;
uniform float seed = 0.0;
// The way the coolant runs, in the quad's UV frame (unit).
uniform vec2 flow = vec2(0.0, 1.0);
// The quad's edge in metres (the shape is in metres round its middle).
uniform float size = 3.6;
// How much of it is coolant (0 a pool of oil alone).
uniform float coolant = 1.0;
uniform vec3 oil_color = vec3(0.012, 0.010, 0.008);
uniform vec3 coolant_color = vec3(0.018, 0.075, 0.012);
uniform vec3 damp_color = vec3(0.035, 0.034, 0.032);

float cf_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.731);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = cf_hash(i);
	float b = cf_hash(i + vec2(1.0, 0.0));
	float c = cf_hash(i + vec2(0.0, 1.0));
	float d = cf_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float cf_fbm(vec2 p) {
	return cf_noise(p) * 0.6 + cf_noise(p * 2.3 + 7.1) * 0.3 + cf_noise(p * 5.1 + 3.3) * 0.1;
}

// Distance (m) from p to the segment a-b.
float cf_seg(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - a - ab * t);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float s = clamp(spread, 0.0, 1.0);
	float g = sqrt(s);
	vec2 fl = normalize(flow + vec2(1e-4));
	// Ragged edges: the same noise pushes every edge in and out.
	float n = cf_fbm(p * 2.2) - 0.5;
	float n2 = cf_fbm(p * 5.5 + 11.0) - 0.5;
	float aa = max(fwidth(length(p)), 0.004);
	// Oil: a small pool under the sump (a little behind the middle), slow to spread.
	vec2 oc = -fl * 0.12;
	float oil_r = 0.14 + 0.36 * g;
	float oil_d = length((p - oc) * vec2(1.0, 0.85)) - oil_r * (1.0 + n * 0.55 + n2 * 0.2);
	float oil = 1.0 - smoothstep(-aa, aa, oil_d);
	// Coolant: a wider sheet, and a tongue run downhill that narrows to a thread.
	float cool_r = 0.2 + 0.62 * g;
	float body = length(p) - cool_r * (1.0 + n * 0.7 + n2 * 0.25);
	float run = 0.15 + 1.35 * s;
	float t_along = clamp(dot(p, fl) / max(run, 0.01), 0.0, 1.0);
	float width = mix(0.22, 0.04, t_along) * (1.0 + n2 * 0.6);
	float tongue = cf_seg(p + vec2(-fl.y, fl.x) * n * 0.25, vec2(0.0), fl * run) - width;
	float cool_d = min(body, tongue);
	float cool = (1.0 - smoothstep(-aa, aa, cool_d)) * coolant;
	// Damp road round the edge (soaked into the asphalt, matte-ish).
	float damp = (1.0 - smoothstep(0.0, 0.16 + 0.1 * g, min(cool_d, oil_d))) * (1.0 - max(cool, oil));
	// Drops flicked out by the hit, a few on the far side.
	vec2 cell = floor(p * 3.0);
	float h = cf_hash(cell + 17.0);
	vec2 dc = (cell + 0.5 + (vec2(cf_hash(cell + 3.0), cf_hash(cell + 9.0)) - 0.5) * 0.7) / 3.0;
	float drop = (h > 0.88 && length(dc) < 1.1 + 0.4 * g) ? 1.0 - smoothstep(0.03, 0.03 + aa, length(p - dc)) : 0.0;
	float c2 = max(cool, drop * coolant);
	// The rainbow film at the oil's rim (thin-film colours, faint).
	float rim = (1.0 - smoothstep(0.0, 0.06, abs(oil_d + 0.03))) * oil;
	vec3 film = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + n2 * 3.0 + length(p) * 2.0));
	vec3 col = damp_color;
	col = mix(col, oil_color + film * 0.025 * rim, oil);
	// Coolant is thin: a wet, glossy darkening with a green tint that deepens where it is thick
	// (away from its edge), never a sheet of paint.
	float thick = clamp(-cool_d / 0.2, 0.0, 1.0);
	col = mix(col, mix(damp_color, coolant_color, 0.35 + 0.65 * thick), c2 * (1.0 - oil));
	float a = max(max(oil * 0.94, c2 * (0.48 + 0.34 * thick)), damp * 0.45);
	ALBEDO = cs_out(col);
	ALPHA = a;
	ROUGHNESS = mix(0.32, 0.04, max(oil, c2));
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
