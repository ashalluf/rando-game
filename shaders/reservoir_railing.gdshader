shader_type spatial;
render_mode cull_disabled;

// The dam's ornamental balustrade panels (LandmarkReservoir): a cast concrete panel pierced with a
// row of round-headed openings, between the posts. UV.x is metres along the panel from its left
// post, UV.y the height over the parapet's base (0 .. RAIL_PANEL_H), so the openings stay whole
// whatever the panel's length; the openings are cut by the shader (discard) - two quads a panel
// rather than thirty boxes. Its own material, so the dam's plain faces never pay for the discard.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/reservoir_concrete.gdshaderinc"

// Opening pitch along the panel, the opening's width, its sill and the top of its straight
// sides (the round head sits on that), metres.
uniform float pitch = 0.42;
uniform float open_w = 0.22;
uniform float sill = 0.16;
uniform float spring = 0.58;
// The panel's length (set per material: the builder spaces the posts evenly, so one length).
uniform float panel_len = 2.4;


void fragment() {
	float u = UV.x;
	float v = UV.y;
	// Openings centred in the panel, a whole number of them.
	float n = max(1.0, floor((panel_len - 0.1) / pitch));
	float u0 = (panel_len - n * pitch) * 0.5;
	float k = (u - u0) / pitch;
	if (k > 0.0 && k < n) {
		float x = (fract(k) - 0.5) * pitch;
		float r = open_w * 0.5;
		bool inside = abs(x) < r && v > sill && (v < spring || length(vec2(x, v - spring)) < r);
		if (inside) {
			discard;
		}
	}
	vec4 c = rc_concrete(vec2(u + COLOR.r * 97.0, v), 0.5, 1.0);
	ALBEDO = cs_out(c.rgb);
	ROUGHNESS = c.a;
}
