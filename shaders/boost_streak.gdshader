shader_type spatial;
// Wind streaks for the player's boost (BoostTrail): each particle is a thin quad stretched along
// its own velocity (the particle's Y axis - CPUParticles3D.particle_flag_align_y) and turned about
// that axis to face the camera, so a streak reads as a line of air from any side. MODEL_MATRIX
// already carries the particle's transform (the instance matrix is folded in before this runs).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 tint : source_color = vec3(0.86, 0.93, 1.0);
// Full width and length of a streak at particle scale 1, in metres.
uniform float width = 0.03;
uniform float streak_length = 2.6;

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
	// A bright hairline core with soft sides, tapering in at the head and fading out down the tail.
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float a = across * across * smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.3, 1.0, along));
	ALBEDO = tint * COLOR.rgb;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
