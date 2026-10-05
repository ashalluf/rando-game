shader_type spatial;
render_mode cull_back;

// The ridges' far solids (RidgeSystem): water tanks, domes, huts, the lookout's cab, the
// substation's transformers and control house as low boxes and cylinders, one mesh for the basin.
// UV2.y is the piece's far id + 1: a piece whose texel in `covered` is set (a FULL chunk has
// built it in detail) is collapsed to nothing. COLOR is sRGB as written (raw on both renderers).

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D covered : filter_nearest, repeat_disable;
uniform int covered_width = 1;

varying vec3 v_col;

void vertex() {
	int i = int(UV2.y + 0.5) - 1;
	if (i >= 0 && texelFetch(covered, ivec2(i % covered_width, i / covered_width), 0).r > 0.5) {
		VERTEX = vec3(0.0);
	}
	v_col = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	ALBEDO = cs_out(v_col);
	ROUGHNESS = 0.6;
}
