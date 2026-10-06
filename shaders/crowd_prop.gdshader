shader_type spatial;
// What the crowd holds (CrowdLife.prop_mesh): a phone, a coffee cup, a shopping bag, a
// cigarette. Colour in the vertex colour (raw on both renderers); UV.x marks what glows: 1 the
// phone's screen (a dim glow, brighter after dark), 2 a cigarette's ember (flickering, bright
// only once the lamps are on). Culling off: the props are a few thin boxes, built in either
// winding.
render_mode cull_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform float screen_glow = 0.35;
uniform float screen_glow_night = 1.4;
uniform float ember_glow = 6.0;

varying float v_glow;
varying vec3 v_colour;

void vertex() {
	v_glow = UV.x;
	v_colour = COLOR.rgb;
}

void fragment() {
	// Vertex colours arrive raw on both renderers: written as sRGB, so decoded here.
	vec3 c = pow(v_colour, vec3(2.2));
	ALBEDO = cs_out(c);
	ROUGHNESS = 0.55;
	if (v_glow > 1.5) {
		float flicker = 0.75 + 0.25 * sin(TIME * 11.0 + c.r * 40.0) * sin(TIME * 3.7);
		EMISSION = cs_out(vec3(1.0, 0.32, 0.06) * ember_glow * lamp_factor * flicker);
		ALBEDO = cs_out(vec3(0.25, 0.08, 0.03));
	} else if (v_glow > 0.5) {
		EMISSION = cs_out(c * mix(screen_glow, screen_glow_night, lamp_factor));
		ROUGHNESS = 0.15;
	}
}
