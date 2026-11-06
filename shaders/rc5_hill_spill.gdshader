shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Light a hill home's lit rooms and pool throw on the terrace (Rc5HillHome): quads laid on the
// paving in front of each lit ground-floor glass wall and round the pool's rim. COLOR.rgb the
// light's colour as display numbers, COLOR.a its strength; UV.x metres along the source, UV.y
// metres out from it, UV2.x the source's length, UV2.y how far the quad reaches. Off by day
// (lamp_factor). Added in display numbers and decoded on Forward+ (fwd-review-e: a broad pool added
// in linear HDR is a flat bright carpet there). fog_disabled: a blend_add quad left in the fog
// adds the fog colour over the whole quad (additive_fog.gdshaderinc's note).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float night_factor;

// Panes this wide along a glass wall: the mullions' shadows in the spill.
uniform float pane = 2.3;


float h11(float p) {
	return fract(sin(p * 127.1 + 31.7) * 43758.5453);
}


void fragment() {
	float on = clamp(max(lamp_factor, night_factor), 0.0, 1.0);
	float x = UV.x;
	float d = max(UV.y, 0.0);
	float len = max(UV2.x, 0.01);
	float reach = max(UV2.y, 0.1);
	// Out from the source: bright at the sill, falling off like a window's light on a floor.
	float fall = exp(-d * 2.6 / reach) * (1.0 - smoothstep(reach * 0.75, reach, d));
	// Along it: fading at the ends, the mullions' shadows, the panes a little uneven.
	float ends = smoothstep(0.0, 0.6, x) * smoothstep(0.0, 0.6, len - x);
	float pi = floor(x / pane);
	float fp = fract(x / pane);
	float dm = min(fp, 1.0 - fp) * pane;
	float mull = 1.0 - 0.5 * (1.0 - smoothstep(0.03, 0.12 + d * 0.06, dm));
	float uneven = 0.8 + 0.2 * h11(pi + COLOR.a * 17.0);
	vec3 c = COLOR.rgb * COLOR.a * fall * ends * mull * uneven * on;
	ALBEDO = cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}
