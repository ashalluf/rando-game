// A window-washing cradle's wire ropes and the crew's lanyards (GondolaRig, rc5-tower-gondola):
// TowerGondolas.unit_cylinder() stretched between two points, its radius in the node's basis.
// A 9-11 mm wire rope thirty metres off is a tenth of a pixel, so the plain cylinder drew nothing
// (or a dashed alias) and the cradle hung on nothing. Here the tube is widened in the vertex stage
// to at least `min_px` pixels across and its real width goes into ALPHA (utility_wire.gdshader's
// rule), so the ropes read as the hairlines a camera sees, faded with distance. Round shading when
// it is wide enough to show it, a camera-facing sheen when it is a hairline. Linear on both
// renderers (color_space.gdshaderinc). Shader files use // comments.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/color_space.gdshaderinc"

uniform vec4 rope_color : source_color = vec4(0.32, 0.33, 0.34, 1.0);
uniform float metal = 0.35;
uniform float rough = 0.45;
// Narrowest a rope is drawn, in pixels across; coverage under it goes into alpha (raised to the
// gamma: a hairline stays readable without thickening).
uniform float min_px = 1.4;
uniform float coverage_gamma = 0.55;
uniform float fade_start = 160.0;
uniform float fade_end = 320.0;

varying float v_alpha;
varying float v_cover;

void vertex() {
	// The tube's radius in metres (the basis' x column; y is the length).
	float r = length(MODEL_MATRIX[0].xyz);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 c = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	float depth = max(-c.z, 0.05);
	// Metres per pixel at this depth. VIEWPORT_SIZE has read 0 in a vertex stage before, and
	// [1][1] is negative on Compatibility.
	float vh = VIEWPORT_SIZE.y > 120.0 ? VIEWPORT_SIZE.y : 1080.0;
	float px = 2.0 * depth / (max(abs(PROJECTION_MATRIX[1][1]), 0.1) * vh);
	float w = max(r, 0.5 * min_px * px);
	float k = w / max(r, 1e-5);
	VERTEX.xz *= k;
	v_cover = r / max(px, 1e-5);
	v_alpha = pow(r / w, coverage_gamma) * (1.0 - smoothstep(fade_start, fade_end, depth));
}

void fragment() {
	if (v_alpha < 0.004) {
		discard;
	}
	// A hairline faces the camera (its grazing rim alone would turn it pale against the sky).
	float detail = smoothstep(0.75, 2.5, v_cover);
	NORMAL = normalize(mix(VIEW, NORMAL, detail));
	ALBEDO = cs_out(cs_in(rope_color.rgb));
	METALLIC = metal;
	ROUGHNESS = rough;
	ALPHA = clamp(v_alpha, 0.0, 1.0);
}
