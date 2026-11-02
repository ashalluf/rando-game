shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// A police station's lettering (PoliceStation._texts()): brushed metal channel letters by day,
// lit from inside after dark by lamp_factor - the department's name over the canopy reads from
// down the street at night like a real station's. Linear on both renderers (color_space).
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// The letters' face colour by day (sRGB, decoded by cs_in) and the light inside them (linear).
uniform vec4 face : source_color = vec4(0.94, 0.92, 0.86, 1.0);
uniform vec3 glow = vec3(1.0, 0.93, 0.80);
uniform float energy = 3.0;

void fragment() {
	vec3 c = cs_in(face.rgb);
	ALBEDO = cs_out(c);
	ROUGHNESS = 0.4;
	METALLIC = 0.3;
	EMISSION = cs_out(glow * energy * lamp_factor);
}
