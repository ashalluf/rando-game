shader_type spatial;
render_mode cull_back, shadows_disabled;

// A night-life venue's name (NightLife, NightLifeKit.sign_material()): TextMesh lettering on a
// club canopy's fascia or a bar's lightbox, in the venue's colour - painted metal by day, lit
// neon-bright after dark (lamp_factor). `tint` is set as a Vector3 (linear on both renderers,
// color_space.gdshaderinc), never a Color (a Color set from script is decoded on Forward+).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform vec3 tint = vec3(1.0, 0.6, 0.3);
uniform float night_energy = 7.0;
uniform float day_energy = 0.15;

void fragment() {
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	vec3 c = tint;
	ALBEDO = cs_out(c * 0.6);
	ROUGHNESS = 0.35;
	EMISSION = cs_out(c * mix(day_energy, night_energy, lamp));
}
