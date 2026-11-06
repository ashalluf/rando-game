shader_type spatial;
// A blast's sparks (Blast3's BlastBits): each instance a thin quad stretched along its own Y axis
// (the spark's velocity, its length the streak's length in metres) and turned about it to face the
// camera, as spark_streak.gdshader does - but the WIDTH is the instance's X scale here, so a spark
// skidding on the road can be a short fat glint and one in the air a long thin line. COLOR is the
// instance colour (linear HDR temperature written by the script; raw on both renderers, handed
// over with cs_out()), alpha its fade.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

uniform float energy = 3.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	axis /= max(len, 1e-5);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 side = cross(axis, CAMERA_POSITION_WORLD - origin);
	side /= max(length(side), 1e-5);
	// Never thinner than about a pixel and a half at its distance: a skimming spark far off is a
	// glint, not nothing.
	float dist = length(CAMERA_POSITION_WORLD - origin);
	// (VIEWPORT_SIZE can read 0 or 1 in a vertex stage: fall back to 1080 lines.)
	float vh = VIEWPORT_SIZE.y > 100.0 ? VIEWPORT_SIZE.y : 1080.0;
	float px = min(dist * 2.0 / max(abs(PROJECTION_MATRIX[1][1]) * vh, 1.0), 0.05);
	w = max(w, px * 1.5);
	vec3 world = origin + side * VERTEX.x * w + axis * (VERTEX.y - 0.5) * len;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float a = across * across * (1.0 - smoothstep(0.15, 1.0, UV.y)) * smoothstep(0.0, 0.1, UV.y);
	ALBEDO = cs_out(COLOR.rgb) * energy;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
