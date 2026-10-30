// The corner store's glass while the real interior is shown (CornerStoreSite): clear, a faint
// green-grey tint, the reflection by Fresnel. Also the cooler doors' glass, always.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 tint = vec3(0.6, 0.66, 0.64);
uniform float base_alpha = 0.08;
uniform float edge_alpha = 0.55;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = cs_out(tint * 0.1);
	ALPHA = mix(base_alpha, edge_alpha, f);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
