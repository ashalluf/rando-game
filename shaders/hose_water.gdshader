shader_type spatial;
// The water out of a fire hose (EmergencyCrew): each particle is a quad stretched along its own
// velocity (CPUParticles3D.particle_flag_align_y) and turned about it to face the camera, like
// the boost streaks (shaders/boost_streak.gdshader), so a few dozen particles read as a solid
// rope of water breaking up into drops at its far end. Unshaded but dimmed with the night (the
// stream is white water lit by the day; at night it is what the street light catches of it).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

// Linear colour of the water (white with a little of the sky in it).
uniform vec3 tint = vec3(0.78, 0.84, 0.90);
// Full width and length of a streak at particle scale 1 (m), and its opacity.
uniform float width = 0.075;
uniform float streak_length = 0.9;
uniform float opacity = 0.62;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float s = length(axis);
	axis /= max(s, 1e-5);
	vec3 side = cross(axis, CAMERA_POSITION_WORLD - origin);
	side /= max(length(side), 1e-5);
	vec3 world = origin + side * VERTEX.x * width * s + axis * VERTEX.y * streak_length * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float a = smoothstep(0.0, 0.6, across) * smoothstep(0.0, 0.15, along) * (1.0 - smoothstep(0.55, 1.0, along));
	float lit = mix(1.0, 0.22, night_factor);
	ALBEDO = cs_out(tint * lit * COLOR.rgb);
	ALPHA = clamp(a * opacity * COLOR.a, 0.0, 1.0);
}
