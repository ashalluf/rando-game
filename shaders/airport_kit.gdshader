shader_type spatial;
render_mode cull_back;

// The airport's small hardware (AirportKit): ground service vehicles, masts, light fixtures,
// navaids, cones, blast fences. One material for all of it; what each vertex is rides in its
// vertex colour's alpha, and the vehicles' livery in the instance's INSTANCE_CUSTOM:
//   a 1.0   painted body: albedo = INSTANCE_CUSTOM.rgb when its alpha is set, else the vertex colour
//   a 0.75  lamp lens: the vertex colour, emitting at night (beacons, cab lamps, fixture lenses)
//   a 0.5   glass: dark, glossy
//   a 0.25  rubber / black plastic: rough
//   a 0.0   anything else: the vertex colour, painted metal
// Colours are LINEAR on both renderers (color_space.gdshaderinc); vertex colours and instance
// data arrive raw on both, so they are written linear in AirportKit.
// Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

varying vec3 v_col;
varying float v_kind;

void vertex() {
	v_col = COLOR.rgb;
	v_kind = COLOR.a;
	if (COLOR.a > 0.9 && INSTANCE_CUSTOM.a > 0.5) {
		v_col = INSTANCE_CUSTOM.rgb;
	}
}

void fragment() {
	vec3 col = v_col;
	float rough = 0.62;
	float metal = 0.15;
	vec3 emit = vec3(0.0);
	if (v_kind > 0.9) {
		rough = 0.42;
		metal = 0.05;
	} else if (v_kind > 0.6) {
		emit = col * (0.15 + 3.5 * lamp_factor);
		rough = 0.2;
	} else if (v_kind > 0.4) {
		col = col * 0.35;
		rough = 0.08;
		metal = 0.3;
	} else if (v_kind > 0.15) {
		rough = 0.92;
		metal = 0.0;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = cs_out(emit);
}
