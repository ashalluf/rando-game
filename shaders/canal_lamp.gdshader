shader_type spatial;
render_mode cull_back;

// The glass of the canal's lanterns (porch lanterns, the bridges' lamp posts; CanalKit): frosted
// glass by day, a warm glow after dark from `lamp_factor` (the street lamps' level, which comes on
// in a storm too). Emitted, so it reads on the web where the lantern has no real light.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

// Linear.
uniform vec3 glass_day = vec3(0.55, 0.55, 0.50);
uniform vec3 glow_color = vec3(1.0, 0.62, 0.28);
uniform float glow_energy = 5.0;

void fragment() {
	ALBEDO = cs_out(glass_day * (1.0 - 0.8 * lamp_factor));
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
	// Brighter toward the middle of each pane: the bulb behind it.
	vec2 c = abs(fract(UV * 3.0) - 0.5);
	float core = 1.0 - 0.35 * max(c.x, c.y);
	EMISSION = cs_out(glow_color * glow_energy * lamp_factor * core);
}
