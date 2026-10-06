shader_type spatial;
// The walk of fame's lamp medallions (StarBoulevard.medallion_mesh()): a neon tube round each gold
// star, a dim warm glass tube by day, glowing after dark with lamp_factor. A slow shimmer per
// medallion (its true world position through origin_shift) so a row does not pulse in step.
render_mode cull_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform vec3 origin_shift;
// Linear: a warm gold-pink neon.
uniform vec3 neon = vec3(1.0, 0.42, 0.18);
uniform float energy = 5.0;

varying float v_phase;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + origin_shift;
	v_phase = fract(sin(dot(w.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float on = clamp(lamp_factor, 0.0, 1.0);
	float shimmer = 0.92 + 0.08 * sin(TIME * 7.0 + v_phase * 40.0);
	ALBEDO = cs_out(mix(vec3(0.55, 0.40, 0.32), neon * 0.4, on));
	ROUGHNESS = 0.25;
	EMISSION = cs_out(neon * (0.15 + energy * on * shimmer));
}
