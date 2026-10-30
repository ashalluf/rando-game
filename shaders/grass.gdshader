shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
#include "res://shaders/heli_downwash.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/lawn_field.gdshaderinc"

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

// The close-up pass (lawns_closeup on, LawnsCloseup; docs/HANDOFF.md "Lawns close up"). A tuft
// then carries the lawn it stands on: COLOR the lawn's tint (sRGB, times the tuft's jitter),
// INSTANCE_CUSTOM.y its dryness, .z its seed index / 1024 (exact in a half float: the seed
// uniform is index x 0.37), .w the metres to the lawn's edge, plus 16 when the lawn is striped.
// The blade's colour is lawn.gdshader's own field at its root times the grass texture's mean, so
// grass and ground agree; and the blades shrink away into the ground between fade_start and
// fade_end metres from the camera, well before their 32 m cell stops drawing (grass_distance is
// measured to the cell's centre), so there is no line where the grass ends.
uniform float fade_start = 26.0;
uniform float fade_end = 62.0;
// lawn.gdshader's defaults (PropFactory.lawn() never sets them): the dry and dirt tints, how
// strong its stripes and its wear are, and the grass texture's mean colour (Grass004's 1K colour
// map, measured: sRGB for Compatibility, decoded for Forward+) - the checks read both files.
uniform vec3 lawn_dry_tint : source_color = vec3(0.62, 0.58, 0.30);
uniform vec3 lawn_dirt_tint : source_color = vec3(0.34, 0.28, 0.20);
const float LAWN_STRIPE_AMOUNT = 0.075;
const float LAWN_WEAR = 0.30;
const float LAWN_STRIPE_WIDTH = 3.4;
const vec3 GRASS_MEAN_SRGB = vec3(0.3780, 0.4258, 0.1897);
const vec3 GRASS_MEAN_LINEAR = vec3(0.1269, 0.1612, 0.0343);
global uniform float night_factor;
global uniform float city_hour;
varying flat vec4 lawn_info;
varying flat vec2 root_xz;
varying float blade_rand;


void vertex() {
	height_t = clamp(UV.y, 0.0, 1.0);
	tuft_rand = INSTANCE_CUSTOM.x;
	lawn_info = INSTANCE_CUSTOM;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	root_xz = root.xz;
	blade_rand = 0.5;
	if (lawn_field_on()) {
		// Each blade its own height: UV.x is the blade's place in the tuft (LawnsCloseup's mesh).
		blade_rand = lf_hash(vec2(INSTANCE_CUSTOM.x * 97.0, UV.x * 31.0 + 1.3));
		float lseed = round(INSTANCE_CUSTOM.z * 1024.0) * 0.37;
		// The ground under the tuft, first octaves only (per vertex): dry grass stands shorter,
		// clover lower still, a worn patch is flattened into the dirt.
		float dry_v = clamp(lf_noise(root.xz * 0.055 + lseed * 1.7) * 0.9 + (INSTANCE_CUSTOM.y - 0.5) * 0.8, 0.0, 1.0);
		float wear_v = smoothstep(0.6, 0.86, lf_noise(root.xz * 0.09 + 57.0 + lseed)) * LAWN_WEAR;
		float clover_v = smoothstep(0.62, 0.8, lf_noise(root.xz * 0.31 + lseed * 3.1 + 71.0)) * (1.0 - smoothstep(0.35, 0.75, dry_v));
		float grow = (0.72 + 0.56 * blade_rand) * (1.0 - 0.32 * dry_v) * (1.0 - 0.45 * clover_v) * (1.0 - 2.6 * wear_v);
		// The uncut fringe along the lawn's edge (mod(w, 16) metres to it) stands taller.
		float edge = mod(INSTANCE_CUSTOM.w, 16.0);
		grow *= 1.0 + 0.45 * (1.0 - smoothstep(0.1, 0.7, edge));
		// Away into the ground with distance, the tip first.
		float dist = length(root - CAMERA_POSITION_WORLD);
		grow *= 1.0 - smoothstep(fade_start, fade_end, dist);
		VERTEX *= max(grow, 0.0);
	}
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
	VERTEX += heli_wash_grass(MODEL_MATRIX, world, height_t, max(VERTEX.y, 0.0), TIME);
}


void fragment() {
	if (lawn_field_on()) {
		vec2 wp = root_xz;
		float lseed = round(lawn_info.z * 1024.0) * 0.37;
		float edge = mod(lawn_info.w, 16.0);
		float stripes = lawn_info.w >= 15.99 ? LAWN_STRIPE_WIDTH : 0.0;
		float dry = lf_dry(wp, lseed, lawn_info.y, edge);
		float clover = lf_clover(wp, lseed, dry);
		float wear = lf_wear(wp, lseed, LAWN_WEAR);
		float stripe = lf_stripe(wp, lseed, stripes);
		// COLOR is the lawn's tint in sRGB (a MultiMesh colour arrives raw on both renderers); the
		// lawn's own tint is a source_color uniform, so take it the way the renderer took that.
		vec3 tint = cs_as_uniform(COLOR.rgb);
		vec3 col = lf_tone(wp, lseed, tint, lawn_dry_tint, lawn_dirt_tint, dry, clover, stripe, LAWN_STRIPE_AMOUNT, wear);
		col *= cs_linear_renderer() ? GRASS_MEAN_LINEAR : GRASS_MEAN_SRGB;
		// Blade by blade: a few yellowed or burnt at the tip, a few bluer and younger, each its
		// own shade - real turf is never one green.
		float h = height_t;
		vec3 shade = mix(vec3(0.62, 0.66, 0.58), vec3(1.14, 1.12, 1.05), smoothstep(0.0, 0.85, h));
		shade *= 0.84 + 0.32 * blade_rand;
		float tip_burn = step(0.82, fract(blade_rand * 7.31)) * smoothstep(0.55, 1.0, h);
		shade = mix(shade, vec3(1.45, 1.22, 0.70), tip_burn * 0.7);
		float young = step(fract(blade_rand * 3.77), 0.2);
		shade *= mix(vec3(1.0), vec3(0.94, 1.06, 1.1), young);
		// Straw blades are straw all the way down, a little paler toward the tip.
		shade = mix(shade, mix(vec3(0.9), vec3(1.12), h), dry * 0.5);
		col *= shade;
		// The morning's watering beads on the blades: darker and glossy.
		float spray = city_hour < 11.0 ? lf_sprinkler(wp, lseed, city_hour) : 0.0;
		float wet = max(clamp(road_wetness, 0.0, 1.0), spray);
		vec3 lit = col * mix(1.0, 0.82, wet);
		// lawn.gdshader's night: open grass gets skylight only, dim and blue-grey.
		float nf = clamp(night_factor, 0.0, 1.0) * 0.72;
		float grey = dot(lit, vec3(0.299, 0.587, 0.114));
		lit = mix(lit, mix(vec3(grey), vec3(grey * 0.78, grey * 0.84, grey * 1.05), 0.7) * 0.30, nf);
		ALBEDO = lit;
		ROUGHNESS = mix(blade_roughness, wet_roughness, wet);
		SPECULAR = mix(blade_specular, 0.85, wet);
		vec3 through = ALBEDO * translucency * (0.25 + 0.95 * height_t) * (1.0 - nf);
		vec3 to_cam_c = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float facing_c = clamp(dot(to_cam_c, -normalize(sun_direction)), 0.0, 1.0);
		BACKLIGHT = through * (1.0 + scatter_gain * pow(facing_c, scatter_sharpness));
	} else {
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
}
