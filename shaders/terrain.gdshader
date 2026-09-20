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
uniform vec3 dry_tint : source_color = vec3(0.86, 0.74, 0.44);
uniform float dry_amount : hint_range(0.0, 1.0) = 0.62;
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 0.95);
uniform vec3 rock_tint : source_color = vec3(1.0, 0.95, 0.9);
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
	dry = clamp(smoothstep(0.30, 0.78, dry) + height_t * 0.35, 0.0, 1.0) * dry_amount;
	g = mix(g, g * dry_tint * 1.35, dry);
	vec3 r = texture(rock_albedo, uv * 0.7).rgb * rock_tint;
	float rocky = clamp(slope * 3.0 + height_t * 1.2 - 0.3, 0.0, 1.0);
	ALBEDO = mix(g, r, rocky);
	NORMAL_MAP = mix(texture(grass_normal, uv).rgb, texture(rock_normal, uv * 0.7).rgb, rocky);
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.95, 0.85, rocky);
}
