shader_type spatial;
// Sparks off a body scraping the road or grinding a wall (DrivingFX): each particle a thin quad
// stretched along its own velocity (CPUParticles3D.particle_flag_align_y puts that on the
// particle's Y axis) and turned about it to face the camera - boost_streak.gdshader's trick - so a
// spark is a short white-hot line that cools to orange and red as it falls (COLOR, from the
// emitter's ramp; vertex colours arrive raw on both renderers, so the ramp is written linear and
// handed over with cs_out()).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/color_space.gdshaderinc"

// HDR gain on the ramp's colour: sparks are brighter than anything lit.
uniform float energy = 4.0;
// Width and length of a spark at particle scale 1, in metres.
uniform float width = 0.026;
uniform float streak_length = 0.5;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float s = length(axis);
	axis /= max(s, 1e-5);
	vec3 side = cross(axis, CAMERA_POSITION_WORLD - origin);
	side /= max(length(side), 1e-5);
	// The head leads; the tail trails back along the velocity.
	vec3 world = origin + side * VERTEX.x * width * s + axis * (VERTEX.y - 0.5) * streak_length * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	// UV.y 0 is the head (+Y end of the quad): bright there, fading down the tail.
	float a = across * across * (1.0 - smoothstep(0.1, 1.0, UV.y)) * smoothstep(0.0, 0.08, UV.y);
	ALBEDO = cs_out(COLOR.rgb) * energy;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
