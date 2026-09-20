shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Wind for the textured leaf cards of the downloaded trees and bushes. Only the leaf surfaces
// use this; the trunk and branches stay on their own opaque material and stay still, which is
// close enough at these amplitudes and keeps the trunks out of the transparent pass.
//
// Same idea as shaders/foliage.gdshader: the bend grows with the square of the height above the
// instance's own origin and the phase comes from the instance's world position, so a row of
// street trees does not move in step.

global uniform float wind_factor;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float alpha_cut = 0.45;

// Small: leaves move relative to the branches they hang off, they do not swing like a crown.
uniform float bend_scale = 0.0009;
uniform float flutter = 0.02;
uniform float speed = 1.15;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	float t = TIME * speed;
	float gust_x = sin(t + phase) * 0.72 + sin(t * 1.73 + phase * 2.1) * 0.28;
	float gust_z = sin(t * 0.87 + phase * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + phase) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gust_x;
	VERTEX.z += bend * gust_z;
	float radial = length(VERTEX.xz);
	VERTEX.y += sin(t * 2.7 + phase + radial * 1.9) * radial * flutter * w * 0.2;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 c = texture(albedo_tex, uv) * base_color * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = has_rough ? texture(rough_tex, uv).r : 0.9;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	SPECULAR = 0.3;
	// A little light through the leaves, which is most of what makes a canopy read as foliage.
	BACKLIGHT = vec3(0.12, 0.16, 0.09);
}
