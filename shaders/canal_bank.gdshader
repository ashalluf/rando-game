shader_type spatial;
render_mode cull_back;

// The canals' banks and bed (Canals._banks()): grass and low planting on the dry upper bank, a
// dark wet band where the water laps, silt and algae below it. UV is world XZ in metres (a chunk's
// local space is true world space), UV2.x the height over the water, UV2.y the slope's up
// component. Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;
global uniform float ground_detail;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float water_y = -0.62;
// Linear tints.
uniform vec3 grass_tint = vec3(0.62, 0.74, 0.46);
uniform vec3 mud_tint = vec3(0.42, 0.40, 0.34);
uniform vec3 algae = vec3(0.045, 0.060, 0.030);
uniform vec3 wet_dark = vec3(0.10, 0.09, 0.07);

varying vec2 v_h;

float bank_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bank_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bank_hash(i), bank_hash(i + vec2(1.0, 0.0)), f.x),
		mix(bank_hash(i + vec2(0.0, 1.0)), bank_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_h = UV2;
}

void fragment() {
	vec2 p = UV;
	float h = v_h.x;
	float n = bank_noise(p * 0.45) * 0.6 + bank_noise(p * 2.3) * 0.4;
	vec3 grass = cs_in(texture(grass_tex, p * 0.35).rgb) * grass_tint;
	vec3 mud = cs_in(texture(mud_tex, p * 0.4).rgb) * mud_tint;
	if (ground_detail > 0.5) {
		grass = mix(grass, cs_in(texture(grass_tex, p * 0.11 + vec2(0.37, 0.71)).rgb) * grass_tint, 0.4);
	}
	// Grass from a ragged line a little over the water; the bare silt under it.
	float edge = 0.32 + (n - 0.5) * 0.35;
	float g = smoothstep(edge, edge + 0.14, h);
	vec3 col = mix(mud, grass, g);
	// The wet band the lap of the water keeps dark, and the algae under the surface.
	float wet = 1.0 - smoothstep(0.0, 0.16 + n * 0.1, h);
	col = mix(col, wet_dark, wet * 0.75);
	float under = 1.0 - smoothstep(-0.08, 0.02, h);
	col = mix(col, algae * (0.7 + 0.6 * n), under * 0.85);
	// Rain darkens the dry bank.
	col *= 1.0 - 0.35 * road_wetness * g;
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(0.9, 0.45, max(wet, road_wetness * 0.6));
	SPECULAR = 0.4;
}
