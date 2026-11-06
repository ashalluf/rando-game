shader_type spatial;
render_mode cull_back;

// The marina's bulkhead faces (MarinaNight, scripts/world/marina_night.gd; MarinaBuild._bulkhead()):
// a harbour wall is never the clean pale concrete of a pavement. Precast panels with their joints,
// the tide zone a hand or two over the water dark and slick with weed and barnacle crust, a wet
// band over it the chop keeps splashing, rust and drip streaks down from the coping's drains and
// cleats, and the whole face darker and greener where the sun never dries it.
//
// UV is (metres along the wall, world height): MarinaBuild.tri() writes it so for a vertical face.
// Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 3.0;
// LINEAR: the concrete's tint and the weed's.
uniform vec3 tint = vec3(0.50, 0.49, 0.46);
uniform vec3 weed = vec3(0.020, 0.026, 0.016);
uniform vec3 crust = vec3(0.10, 0.10, 0.085);
uniform vec3 rust = vec3(0.16, 0.075, 0.03);
// The water's level (Marina.WATER_Y), the tide zone over it and the splash band over that (m).
uniform float water_y = 0.15;
uniform float tide = 0.55;
uniform float splash = 0.5;
// Precast panel width (m).
uniform float panel = 6.0;
// The coping's top (Marina.QUAY_Y + CityChunk.SIDEWALK_TOP), where the streaks start.
uniform float coping_y = 2.05;

float sw_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sw_hash(i), sw_hash(i + vec2(1.0, 0.0)), f.x), mix(sw_hash(i + vec2(0.0, 1.0)), sw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 tuv = uv / tile;
	vec3 tex = cs_in(texture(albedo_tex, tuv).rgb);
	float lum = dot(tex, vec3(0.333));
	// The concrete, its mottle and a weathered, darker look than the pavement's.
	float mott = sw_noise(uv * vec2(0.6, 1.2)) * 0.6 + sw_noise(uv * 3.1) * 0.4;
	vec3 alb = tint * (0.55 + 0.9 * lum) * (0.8 + 0.3 * mott);
	float rough = texture(rough_tex, tuv).r;
	float h = uv.y - water_y;
	// Panel joints: a dark vertical seam every `panel` metres, a horizontal lift line.
	float jx = abs(fract(uv.x / panel + 0.5) - 0.5) * panel;
	float fw = max(fwidth(uv.x), 1e-4);
	float joint = 1.0 - smoothstep(0.015, 0.015 + fw * 1.5, jx);
	float jy = abs(fract((uv.y - 0.9) / 1.5 + 0.5) - 0.5) * 1.5;
	float lift = (1.0 - smoothstep(0.006, 0.006 + max(fwidth(uv.y), 1e-4) * 1.5, jy)) * 0.5;
	alb *= 1.0 - 0.55 * max(joint, lift);
	// Streaks down from the coping: drains and cleats every few metres, rust or grime.
	float col = floor(uv.x / 1.7);
	float sx = (fract(uv.x / 1.7) - 0.5) * 1.7;
	float pick = sw_hash(vec2(col, 7.3));
	float width = 0.06 + 0.22 * sw_hash(vec2(col, 2.1));
	float reach = 0.6 + 1.6 * sw_hash(vec2(col, 5.9));
	float top_y = coping_y;
	float streak = (1.0 - smoothstep(width * 0.4, width, abs(sx + (sw_noise(vec2(uv.y * 3.0, col)) - 0.5) * 0.06)))
		* smoothstep(top_y - reach, top_y - 0.1, uv.y) * step(0.45, pick);
	vec3 stain = mix(vec3(0.05, 0.05, 0.045), rust, step(0.8, pick));
	alb = mix(alb, stain, streak * 0.55);
	// The splash band: darker, wet, ragged at the top.
	float edge_n = (sw_noise(uv * vec2(1.3, 4.0)) - 0.5) * 0.25;
	float wet = 1.0 - smoothstep(tide + splash + edge_n - 0.1, tide + splash + edge_n + 0.05, h);
	alb *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.35, wet);
	// The tide zone: barnacle crust grading into weed toward the water, slick.
	float tz = 1.0 - smoothstep(tide + edge_n * 0.6 - 0.04, tide + edge_n * 0.6 + 0.04, h);
	float bumps = sw_noise(uv * 18.0);
	vec3 zone = mix(weed, crust * (0.7 + 0.6 * bumps), smoothstep(0.0, tide, h) * smoothstep(0.35, 0.7, sw_noise(uv * vec2(2.5, 6.0))));
	alb = mix(alb, zone, tz);
	rough = mix(rough, 0.22, tz);
	// Rain wets the whole face.
	alb *= mix(1.0, 0.7, clamp(road_wetness, 0.0, 1.0));
	ALBEDO = cs_out(alb);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	NORMAL_MAP = texture(normal_tex, tuv).rgb;
	NORMAL_MAP_DEPTH = mix(0.8, 1.6, tz);
}
