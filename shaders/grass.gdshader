shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Grass blade for a MultiMesh: the top of each blade sways with the wind.
// INSTANCE_CUSTOM.x is a per-blade phase, COLOR is the blade tint.

uniform float wind_strength = 0.25;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform vec3 base_color : source_color = vec3(0.26, 0.48, 0.20);
uniform vec3 tip_color : source_color = vec3(0.55, 0.75, 0.30);

varying float height_t;


void vertex() {
	height_t = clamp(UV.y, 0.0, 1.0);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831 + world.x * 0.35 + world.z * 0.25;
	float sway = sin(TIME * wind_speed + phase) * 0.6 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.4;
	float bend = height_t * height_t * wind_strength * sway;
	VERTEX.x += bend * wind_dir.x;
	VERTEX.z += bend * wind_dir.y;
}


void fragment() {
	ALBEDO = mix(base_color, tip_color, height_t) * COLOR.rgb;
	ROUGHNESS = 0.95;
}
