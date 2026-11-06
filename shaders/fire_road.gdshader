shader_type spatial;
render_mode cull_back;

// The dirt of the fire roads and the pads on the ridges (Ridges, RidgeBuild): compacted
// decomposed granite, two wheel ruts worn darker and smoother, a hump of dry grass down the
// middle, straw creeping in at the ragged edges, runnels where the winter rain ran down it. A pad
// (UV.x over 1.5) is the same ground without ruts, with tyre-turned patches.
// UV: x across the road 0..1 (2 + anything on a pad), y metres along it. UV2: world x, z (metres,
// for the pad's noise). Works in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// The texture's mean luminance (linear), so the recolour keeps its detail at the colour asked.
uniform float dirt_mean_luma = 0.203;
uniform float tex_scale = 3.2;
uniform float width = 5.0;
// Linear colours: the bed (paler than the hillside's dirt: graded and dusty), the ruts, the straw.
uniform vec3 dirt_color = vec3(0.262, 0.226, 0.172);
uniform vec3 rut_color = vec3(0.196, 0.168, 0.128);
uniform vec3 straw_color = vec3(0.200, 0.158, 0.076);
uniform float keep_hue : hint_range(0.0, 1.0) = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	bool pad = UV.x > 1.5;
	float u = pad ? 0.5 : UV.x;
	vec2 q = pad ? UV2 : vec2((UV.x - 0.5) * width, UV.y);
	vec3 tex = cs_in(texture(dirt_albedo, q / tex_scale).rgb);
	float luma = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = vec3(luma / dirt_mean_luma);
	vec3 detail = mix(grey, tex / dirt_mean_luma, keep_hue);
	float n1 = vnoise(q * 0.35);
	float n2 = vnoise(q * 1.7 + 13.0);
	vec3 col = dirt_color * (0.88 + 0.24 * n1);
	float rough = 0.93;
	float wear = 0.0;
	if (!pad) {
		// Two wheel ruts 1.6 m apart, wandering a little.
		float wob = (vnoise(vec2(UV.y * 0.05, 3.0)) - 0.5) * 0.06;
		float d1 = abs(u - (0.33 + wob));
		float d2 = abs(u - (0.67 + wob));
		wear = smoothstep(0.075, 0.025, min(d1, d2));
		col = mix(col, rut_color * (0.9 + 0.2 * n2), wear * 0.85);
		rough -= wear * 0.12;
		// The grass hump down the middle and the straw at the edges, ragged.
		float hump = smoothstep(0.1, 0.03, abs(u - 0.5 - wob)) * smoothstep(0.35, 0.65, n2 + 0.2 * n1);
		float edge = smoothstep(0.16, 0.0, min(u, 1.0 - u) - (n2 - 0.5) * 0.08);
		col = mix(col, straw_color * (0.8 + 0.4 * n2), clamp(hump * 0.8 + edge, 0.0, 1.0));
		// Runnels cut down the road where the winter rain ran.
		float run = smoothstep(0.92, 0.98, vnoise(vec2(u * 6.0 + UV.y * 0.18, UV.y * 0.05)));
		col *= 1.0 - run * 0.25;
		if (min(u, 1.0 - u) < 0.04 * (0.4 + n2)) {
			discard;
		}
	} else {
		float turned = smoothstep(0.55, 0.75, vnoise(q * 0.18 + 7.0));
		col = mix(col, rut_color, turned * 0.4);
	}
	col *= mix(vec3(1.0), detail, 0.75);
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	NORMAL_MAP = texture(dirt_normal, q / tex_scale).rgb;
	NORMAL_MAP_DEPTH = 0.8 - wear * 0.4;
}
