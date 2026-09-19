shader_type spatial;

// Hills: grass on flat ground, rock on slopes and high up. Textures projected from above
// in world space so they never stretch across chunk seams. Vertex COLOR.r carries height 0..1.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 6.0;
uniform vec3 grass_tint : source_color = vec3(0.9, 1.0, 0.85);
uniform vec3 rock_tint : source_color = vec3(1.0, 0.95, 0.9);

varying vec3 world_pos;
varying float height_t;
varying float slope;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height_t = COLOR.r;
	slope = 1.0 - clamp((MODEL_NORMAL_MATRIX * NORMAL).y, 0.0, 1.0);
}


void fragment() {
	vec2 uv = world_pos.xz / texture_scale;
	vec3 g = texture(grass_albedo, uv).rgb * grass_tint;
	vec3 r = texture(rock_albedo, uv * 0.7).rgb * rock_tint;
	float rocky = clamp(slope * 3.0 + height_t * 1.2 - 0.3, 0.0, 1.0);
	ALBEDO = mix(g, r, rocky);
	NORMAL_MAP = mix(texture(grass_normal, uv).rgb, texture(rock_normal, uv * 0.7).rgb, rocky);
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.95, 0.85, rocky);
}
