shader_type spatial;
render_mode cull_disabled;

// Climbing plants and garden accents (ClimbingPlants, scripts/world/climbing_plants.gd): leaf
// cards and bract clusters built in code to hug a wall, a fence, a pole or a pergola, and the
// accent plants' blades, all cut from ONE painted atlas (tools/make_climbers.py).
//
// Vertex data (written by ClimbingPlants):
//   UV      the atlas texel (the card's cell already applied)
//   COLOR   rgb: a tint multiplier, LINEAR, ~1 (leaf to leaf variety, sun-bleached bracts);
//           a: how free the vertex is to move in the wind (0 pinned to the wall, 1 a hanging
//           strand's tip)
//   NORMAL  already bent toward the plant mass's outward direction (a mass lights as a volume)
//   TANGENT the card's u axis, for the atlas normal map
//   UV2.x   1 for a flower or bract (thinner, more translucent, a little glossier)
//   UV2.y   the distance (m) the card fades out by, dithered over fade_band (its mesh's range)
//
// Colours: the atlas is a `source_color` texture, so the arithmetic runs in linear through
// color_space.gdshaderinc on both renderers (CLAUDE.md, measurement trap 4).

#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;
global uniform float road_wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
/// Atlas size in texels (for the cut-out's mip compensation).
uniform vec2 atlas_size = vec2(2048.0, 1280.0);
/// Cut-out threshold, and how much a mip level lowers it: alpha averages down the mip chain, and
/// without this a mass thins to bare stems at thirty metres.
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float mip_fill : hint_range(0.0, 1.0) = 0.16;
uniform float mip_fill_max : hint_range(0.0, 1.0) = 0.62;

/// Metres a fully free vertex swings at wind 1, and the rates (Hz-ish) of sway and flutter.
uniform float sway : hint_range(0.0, 0.3) = 0.05;
uniform float sway_speed : hint_range(0.0, 4.0) = 0.9;
uniform float flutter : hint_range(0.0, 0.05) = 0.006;
uniform float flutter_speed : hint_range(0.0, 12.0) = 5.5;

uniform float translucency : hint_range(0.0, 1.0) = 0.28;
uniform float flower_translucency : hint_range(0.0, 1.0) = 0.5;
uniform float leaf_roughness : hint_range(0.0, 1.0) = 0.58;
uniform float leaf_specular : hint_range(0.0, 1.0) = 0.38;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.24;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform float fade_band : hint_range(1.0, 60.0) = 25.0;

varying float flower;
varying float fade_far;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float free = COLOR.a;
	float ph = dot(wp.xz, vec2(0.37, 0.21)) + wp.y * 0.11;
	float gust = 0.6 + 0.4 * sin(TIME * 0.21 + wp.x * 0.013 + wp.z * 0.017);
	float w = (0.25 + wind_factor) * gust;
	vec3 swing = vec3(sin(TIME * sway_speed + ph), 0.25 * sin(TIME * sway_speed * 1.3 + ph * 1.7), cos(TIME * sway_speed * 0.83 + ph * 1.3));
	vec3 shiver = vec3(sin(TIME * flutter_speed + wp.y * 9.0 + wp.x * 7.0), sin(TIME * flutter_speed * 1.21 + wp.z * 8.0), cos(TIME * flutter_speed * 0.93 + wp.x * 5.0));
	vec3 d = swing * sway * free * free * w + shiver * flutter * free * w;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * d);
	flower = UV2.x;
	fade_far = UV2.y;
}

void fragment() {
	// Dithered out over the last fade_band metres of the card's reach (TAA smooths the dither).
	float fade = 1.0 - smoothstep(fade_far - fade_band, fade_far, length(VERTEX));
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (fade < dither) {
		discard;
	}
	vec4 t = texture(albedo_tex, UV);
	// The mip level this pixel reads, from the texel footprint.
	vec2 px = UV * atlas_size;
	float lod = 0.5 * log2(max(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px))), 1e-6));
	float cut = alpha_cut * (1.0 - min(max(lod, 0.0) * mip_fill, mip_fill_max));
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	vec3 c = cs_in(t.rgb) * COLOR.rgb;
	float wet = clamp(road_wetness, 0.0, 1.0);
	c *= 1.0 - 0.18 * wet;
	ALBEDO = cs_out(c);
	vec3 nm = texture(normal_tex, UV).rgb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(mix(leaf_roughness, 0.7, flower), wet_roughness, wet);
	SPECULAR = leaf_specular;
	BACKLIGHT = cs_out(c * mix(translucency, flower_translucency, flower));
}
