shader_type spatial;
// The station's glass (MetroBuild): escalator and stair balustrades, the lift shaft, the kiosks'
// canopies. Transparent, both faces, a faint green edge tint and a Fresnel sheen; under the
// street the fixtures' light is emitted on it the way metro_station.gdshader does, so the panes
// do not go black where the sky does not reach.
render_mode blend_mix, cull_disabled, depth_draw_opaque;

#include "res://shaders/color_space.gdshaderinc"

uniform float st_base = 0.0;
uniform vec3 tint = vec3(0.78, 0.86, 0.84);
uniform float opacity = 0.14;

varying float h;

void vertex() {
	h = VERTEX.y - st_base;
}

void fragment() {
	float under = smoothstep(-0.4, -3.0, h);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = cs_out(tint * 0.5);
	EMISSION = cs_out(tint * 0.05 * under);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(opacity + fres * 0.55, 0.0, 0.85);
}
