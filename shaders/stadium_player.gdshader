shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The players on the ballpark's field (StadiumNight.players_mesh): paint in the vertex colour
// (sRGB numbers, raw on both renderers); after dark lit by the light banks like the field
// (ballpark_field's flood term), the tops of shoulders and caps most.

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float flood_energy = 0.5;

varying vec3 paint;

void vertex() {
	paint = bp_vcol(COLOR.rgb);
}

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	ALBEDO = cs_out(paint);
	ROUGHNESS = 0.8;
	EMISSION = cs_out(paint * bp_flood() * flood_energy * (0.55 + 0.45 * clamp(wn.y, 0.0, 1.0)) * vec3(0.95, 0.98, 1.04));
}
