shader_type spatial;

// Hills: grass on flat ground, rock on slopes and high up. Textures projected from above
// in world space so they never stretch across chunk seams. Vertex COLOR.r carries height 0..1.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 5.0;
/// Summer-dry patches. The hills above a California basin are gold and tan by August with
/// darker green only in the gullies, and the source texture is a lush northern green; without
/// this the whole range reads as an English meadow.
/// NOT source_color: this multiplies the sampled grass, so it is already linear. Hinted
/// source_color (as it was) Godot sRGB-decoded it to (0.708, 0.513, 0.164) and fully-dry
/// hillside came out at luminance 0.096 - DARKER than the live grass beside it at 0.126, and
/// rust-red rather than gold. Same mistake commit 890ad3d fixed in nine places on the ground.
uniform vec3 dry_tint = vec3(0.86, 0.74, 0.44);
uniform float dry_amount : hint_range(0.0, 1.0) = 0.62;
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 0.95);
uniform vec3 rock_tint : source_color = vec3(1.0, 0.95, 0.9);
/// Snow on the tops. height_t is (height - 40 m) / 900, so this starts around 700 m.
uniform vec3 snow_color : source_color = vec3(0.86, 0.88, 0.92);
uniform float snow_from : hint_range(0.0, 1.0) = 0.72;
/// Same second fetch as the road shader, and the same global switch. The hill texture has a
/// directional grain, so at a 5 m tile a long slope turns into corduroy.
global uniform float ground_detail;

varying vec3 world_pos;
varying float height_t;
varying float slope;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height_t = COLOR.r;
	slope = 1.0 - clamp((MODEL_NORMAL_MATRIX * NORMAL).y, 0.0, 1.0);
}


float hash12t(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoiset(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12t(i), hash12t(i + vec2(1.0, 0.0)), f.x),
		mix(hash12t(i + vec2(0.0, 1.0)), hash12t(i + vec2(1.0, 1.0)), f.x), f.y);
}


void fragment() {
	vec2 uv = world_pos.xz / texture_scale;
	vec3 g = texture(grass_albedo, uv).rgb * grass_tint;
	if (ground_detail > 0.5) {
		vec2 uv2 = (mat2(vec2(0.74, -0.67), vec2(0.67, 0.74)) * world_pos.xz) / (texture_scale * 1.61) + vec2(7.3, 2.9);
		float blend = smoothstep(0.32, 0.68, vnoiset(world_pos.xz * 0.021 + 5.0));
		g = mix(g, texture(grass_albedo, uv2).rgb * grass_tint, blend);
	}
	// Where the slope has burned off: broad patches, drier on the sunny upper ground, with the
	// green kept in the folds. Two octaves is enough at this scale.
	float dry = vnoiset(world_pos.xz * 0.013) * 0.7 + vnoiset(world_pos.xz * 0.047) * 0.3;
	dry = clamp(smoothstep(0.30, 0.78, dry) + height_t * 0.9, 0.0, 1.0) * dry_amount * (1.0 - smoothstep(0.55, 0.8, height_t));
	g = mix(g, g * dry_tint * 1.35, dry);
	vec3 r = texture(rock_albedo, uv * 0.7).rgb * rock_tint;
	float rocky = clamp(slope * 2.2 + height_t * 2.4 - 0.25, 0.0, 1.0);
	vec3 albedo = mix(g, r, rocky);
	// Snow above the treeline, and not on the near-vertical faces, where it slides off.
	float snow = smoothstep(snow_from, snow_from + 0.22, height_t) * (1.0 - smoothstep(0.45, 0.8, slope));
	albedo = mix(albedo, snow_color, snow);
	ALBEDO = albedo;
	NORMAL_MAP = mix(texture(grass_normal, uv).rgb, texture(rock_normal, uv * 0.7).rgb, rocky);
	NORMAL_MAP_DEPTH = 0.8 * (1.0 - snow * 0.7);
	ROUGHNESS = mix(mix(0.95, 0.85, rocky), 0.62, snow);
}
