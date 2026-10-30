shader_type spatial;
render_mode cull_disabled;

// The canal boats (CanalKit.boat_mesh()): one mesh per kind, its parts in the vertex colour (sRGB)
// and the vertex alpha saying which of them are paint - alpha 0 takes the boat's paint from
// INSTANCE_CUSTOM.rgb (sRGB; the instance COLOR stays white, it would multiply every part), alpha
// 1 keeps its own colour (wood, rubber, the dark waterline). One draw per kind a chunk, however
// many boats. Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform float paint_roughness = 0.36;
uniform float wood_roughness = 0.72;

varying vec3 v_local;
varying vec3 v_paint;

float boat_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	v_local = VERTEX;
	v_paint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float painted = 1.0 - step(0.5, COLOR.a);
	// A painted part's vertex colour is a shade (white, or lighter inside the hull) on the paint.
	vec3 col = cs_srgb_to_linear(COLOR.rgb) * mix(vec3(1.0), cs_srgb_to_linear(v_paint), painted);
	// Grime low on the hull and a little unevenness in the paint.
	float grime = smoothstep(0.05, -0.15, v_local.y) * 0.25;
	float n = boat_hash(floor(v_local * vec3(14.0, 22.0, 14.0)));
	col *= (1.0 - grime) * mix(0.95, 1.04, n);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(wood_roughness, paint_roughness, painted);
	SPECULAR = 0.5;
}
