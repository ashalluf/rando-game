shader_type spatial;
render_mode cull_disabled;

// Wind sway for generated foliage (palms). Nothing in this city moved except the grass, and a
// street of palms standing dead still is one of the things that reads as "model" rather than
// "place". The bend grows with the square of height above the instance's own origin, so a
// trunk barely moves at the base and the crown swings; the outer parts of the mesh (the
// leaflets, which sit furthest from the trunk axis) get an extra flutter on top.
//
// The phase comes from the instance's world position, so a row of palms does not sway in step.

global uniform float wind_factor;

// Metres of sideways bend per metre-squared of height. 0.0015 puts a 15 m palm's crown through
// about a third of a metre.
uniform float bend_scale = 0.0015;
// Extra movement on the parts furthest from the trunk, as a fraction of that distance.
uniform float flutter = 0.045;
uniform float speed = 0.85;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	float t = TIME * speed;
	// Two frequencies so the sway wanders instead of ticking like a metronome.
	float gust_x = sin(t + phase) * 0.72 + sin(t * 1.73 + phase * 2.1) * 0.28;
	float gust_z = sin(t * 0.87 + phase * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + phase) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;
	float radial = length(VERTEX.xz);
	VERTEX.y += sin(t * 3.1 + phase + radial * 1.7) * radial * flutter * w * 0.25;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
}
