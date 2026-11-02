shader_type spatial;
render_mode cull_back;

// The historic core's entrance lanterns and the lit glass over a banking-hall door
// (scripts/world/historic_facade.gd): frosted glass that is a pale warm grey by day and glows
// with the lamps after dark (`lamp_factor`, DayNight's street-lamp level). COLOR.r scales the
// glow (1 a lantern, less for the transom glass), the rest is the glass's day colour.
//
// Shader files use // comments, never #.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform vec3 glass_day : source_color = vec3(0.70, 0.66, 0.58);
uniform vec3 glow_color : source_color = vec3(1.0, 0.78, 0.48);
uniform float glow_energy = 5.0;
// A little glow by day too: an entrance's lamps are often left on.
uniform float day_glow = 0.12;

void fragment() {
	vec3 day = cs_in(glass_day);
	vec3 glow = cs_in(glow_color);
	float on = clamp(lamp_factor, 0.0, 1.0);
	ALBEDO = cs_out(day * (1.0 - 0.7 * on));
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	EMISSION = cs_out(glow * glow_energy * COLOR.r * mix(day_glow, 1.0, on));
}
