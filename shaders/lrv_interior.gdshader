shader_type spatial;
render_mode cull_back;

// The light rail car's real interior box (only seen through an open door: the windows trace their
// own, lrv_glass.gdshader): its surfaces at their colours (the vertex colour, linear, from
// tools/make_light_rail.py), lit like the traced saloon - a share of the sky by day, its own strip
// lights after dark.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform vec4 sky_tint;

uniform float day_light = 0.42;
uniform float night_light = 1.25;


void fragment() {
	float night = clamp(night_factor, 0.0, 1.0);
	vec3 day = max(sky_tint.rgb, vec3(0.0)) * (1.0 - night * 0.92);
	vec3 light = day * day_light + vec3(1.0, 0.93, 0.80) * night * night_light;
	vec3 albedo = COLOR.rgb;
	ALBEDO = cs_out(albedo * 0.2);
	ROUGHNESS = 0.7;
	EMISSION = cs_out(albedo * light);
}
