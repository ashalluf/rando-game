shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// A tuft of grass blades for a MultiMesh: the blades sway with the wind, darken toward the
// ground and pick up a little translucency at the tips.
// INSTANCE_CUSTOM.x is a per-tuft phase, COLOR is the tuft tint, UV.y is height up the blade.

global uniform float wind_factor;
uniform float wind_strength = 0.16;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform vec3 base_color : source_color = vec3(0.13, 0.22, 0.09);
uniform vec3 tip_color : source_color = vec3(0.42, 0.62, 0.22);
// How much darker the very bottom of the tuft is (ambient occlusion into the soil).
uniform float root_shadow = 0.45;

varying float height_t;
varying float tuft_rand;


void vertex() {
	height_t = clamp(UV.y, 0.0, 1.0);
	tuft_rand = INSTANCE_CUSTOM.x;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831 + world.x * 0.35 + world.z * 0.25;
	// Two frequencies so gusts roll across the lawn instead of every blade ticking in unison.
	float sway = sin(TIME * wind_speed + phase) * 0.6 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.4;
	float bend = height_t * height_t * wind_strength * max(wind_factor, 0.2) * sway;
	VERTEX.x += bend * wind_dir.x;
	VERTEX.z += bend * wind_dir.y;
}


void fragment() {
	// Grass is darkest and yellowest at the soil, greenest and brightest at the tips.
	vec3 col = mix(base_color, tip_color, height_t * height_t);
	col *= COLOR.rgb;
	// Per-tuft variation so a lawn is never one flat colour.
	col *= 0.82 + 0.36 * tuft_rand;
	// Occlusion into the root mat.
	col *= mix(1.0 - root_shadow, 1.0, smoothstep(0.0, 0.45, height_t));
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.18;
	// Thin blades let light through from behind, which is what makes real grass glow when the
	// sun is low and behind it.
	BACKLIGHT = vec3(0.22 * height_t);
}
