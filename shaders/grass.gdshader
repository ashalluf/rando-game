shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// A tuft of grass blades for a MultiMesh: the blades sway with the wind, darken toward the
// ground, and pick up translucency at the tips.
// INSTANCE_CUSTOM.x is a per-tuft phase, COLOR is the tuft tint, UV.y is height up the blade.
//
// This is the densest thing in the city by instance count, so every line here is paid for
// thousands of times a frame. Nothing below samples a texture and nothing below depends on how a
// renderer decodes one, so it looks the same on Forward+ and on the Compatibility renderer the
// web build uses.

global uniform float wind_factor;
/// Weather's wet-surface amount, 0 dry to 1 soaked. Wet grass is darker and far glossier, which
/// is most of what sells rain on a lawn.
global uniform float road_wetness;
/// Points TOWARDS the sun (published by DayNight). Drives the blade-glow lobe.
global uniform vec3 sun_direction;

/// Sideways bend at the blade tip, as a fraction of blade height, and the rate it sways at.
uniform float wind_strength : hint_range(0.0, 1.0) = 0.16;
uniform float wind_speed : hint_range(0.0, 6.0) = 1.6;
uniform vec2 wind_dir = vec2(1.0, 0.3);
/// Rate of the travelling gust envelope, and how deep it cuts. A gust rolls across the lawn
/// instead of every blade holding a constant amplitude forever; it is the same envelope the tree
/// shaders use, at the same rate, so grass and canopy breathe together.
uniform float gust_speed : hint_range(0.0, 1.0) = 0.17;
uniform float gust_depth : hint_range(0.0, 1.0) = 0.45;

uniform vec3 base_color : source_color = vec3(0.13, 0.22, 0.09);
uniform vec3 tip_color : source_color = vec3(0.42, 0.62, 0.22);
/// How much darker the very bottom of the tuft is (ambient occlusion into the soil).
uniform float root_shadow : hint_range(0.0, 1.0) = 0.45;

/// How much light a blade passes through, and how much extra it gets when the camera is looking
/// straight through the lawn at the sun. Thin blades glow when the sun is low and behind them;
/// the forward-scattering lobe is what makes that glow arrive only from the right angle instead
/// of being a flat lift on every blade in the world.
uniform float translucency : hint_range(0.0, 1.0) = 0.24;
uniform float scatter_gain : hint_range(0.0, 4.0) = 1.8;
uniform float scatter_sharpness : hint_range(1.0, 16.0) = 5.0;
uniform float blade_roughness : hint_range(0.0, 1.0) = 0.86;
uniform float blade_specular : hint_range(0.0, 1.0) = 0.22;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.24;

varying float height_t;
varying float tuft_rand;


void vertex() {
	height_t = clamp(UV.y, 0.0, 1.0);
	tuft_rand = INSTANCE_CUSTOM.x;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831 + world.x * 0.35 + world.z * 0.25;
	float w = max(wind_factor, 0.2);
	// The travelling gust envelope, keyed to world position so it crosses the lawn as a wave.
	w *= 1.0 - gust_depth + gust_depth * (0.5 + 0.5 * sin(TIME * gust_speed + (world.x + world.z) * 0.013));
	// Two frequencies so gusts roll across the lawn instead of every blade ticking in unison.
	float sway = sin(TIME * wind_speed + phase) * 0.6 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.4;
	float bend = height_t * height_t * wind_strength * w * sway;
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

	float wet = clamp(road_wetness, 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.80, wet);
	ROUGHNESS = mix(blade_roughness, wet_roughness, wet);
	SPECULAR = mix(blade_specular, 0.85, wet);

	// Thin blades let light through from behind, which is what makes real grass glow when the sun
	// is low and behind it. Tinted by the blade's own colour rather than a flat grey lift, and
	// strongest at the tips, where a blade is thinnest.
	vec3 through = ALBEDO * translucency * (0.25 + 0.95 * height_t);
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = through * (1.0 + scatter_gain * pow(facing, scatter_sharpness));
}
