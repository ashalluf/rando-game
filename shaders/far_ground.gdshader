shader_type spatial;
render_mode specular_disabled;

// The merged ground of a far (LOD) chunk: roads, pavements, lots and lawns in one vertex-coloured
// mesh (CityChunk._add_ground_grid). Far chunks build no street lamps, so after dark every street
// out there was black and the city seen from the air was lit towers standing in a void - where a
// real one is a grid of orange lines. The vertex colour's alpha marks the carriageway and which
// way it runs (1.0 along Z, 0.75 along X, 0.5 a junction, 0.25 a pavement, 0 anything else),
// and the glow comes on with the `lamp_factor` global like the real lamps in the near chunks.
// The pattern and levels match road.gdshader's far glow, so a street does not change as its
// chunk swaps level.

#include "res://shaders/street_glow.gdshaderinc"

varying vec2 plan_pos;


void vertex() {
	// Object space is plan space: the chunk's vertices are laid out in plan coordinates and the
	// streamer moves the holder, so this does not jump when the origin is re-centred.
	plan_pos = VERTEX.xz;
}


void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	float a = COLOR.a;
	if (a > 0.1 && lamp_factor > 0.001) {
		if (a > 0.35) {
			int axis = a > 0.9 ? 1 : (a > 0.6 ? 2 : 0);
			EMISSION = street_glow(plan_pos, axis) * lamp_factor;
		} else {
			// A pavement: the lamps stand on it, so it catches their spill.
			EMISSION = street_glow(plan_pos, 0) * lamp_factor * 0.35;
		}
	}
}
