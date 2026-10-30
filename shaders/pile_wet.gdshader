// A pile of the beach piers (LandmarkBeachPiers' concrete and timber piles, via
// OceanCloseup.pile_material()): its own surface - board-formed concrete or creosoted timber with
// its grain - and the waterline where it stands in the sea (waterline_wet.gdshaderinc). LINEAR.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/waterline_wet.gdshaderinc"

global uniform vec3 origin_shift;
global uniform float ocean_closeup;
uniform vec3 base_color = vec3(0.30, 0.29, 0.27);
uniform float base_rough = 0.85;
// 0 concrete, 1 timber.
uniform float timber = 0.0;

varying vec3 v_world;
varying vec3 v_centre;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_centre = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 rel = v_world.xz - v_centre.xz;
	float around = atan(rel.y, rel.x) * 0.5;
	vec2 w = v_world.xz + origin_shift.xz;
	float n = wl_noise(vec2(around * 4.0, v_world.y * 0.7) + w * 0.01);
	vec3 alb = base_color;
	float rough = base_rough;
	if (timber > 0.5) {
		float grain = wl_noise(vec2(around * 40.0, v_world.y * 1.2));
		alb *= 0.8 + 0.3 * grain;
	} else {
		float lifts = smoothstep(0.85, 0.95, abs(fract(v_world.y / 1.2) - 0.5) * 2.0);
		alb *= (0.85 + 0.25 * n) * (1.0 - 0.15 * lifts);
	}
	if (ocean_closeup > 0.5) {
		alb = wl_wet(alb, v_world.y, w, around, TIME, rough);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
}
