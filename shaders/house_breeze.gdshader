shader_type spatial;
render_mode cull_disabled;

// A mid-century breeze-block screen (HouseKit): a wall of cast concrete blocks with a pattern cut
// through each, the most Los Angeles thing a 1955 house can stand behind. One quad; the holes are
// cut out per pixel from the UV (metres along and up the screen, HouseKit._breeze()), each block
// 40 cm square with its four leaf-shaped openings round a solid centre. Two-sided, so the far side
// shows through the holes. Once a block is under a few pixels the holes are dithered out at their
// own share, so a screen across the street keeps its see-through tone instead of shimmering.
// COLOR.rgb is the paint (sRGB as written).

#include "res://shaders/color_space.gdshaderinc"

uniform float block = 0.4;


float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec2 uv = UV;
	float mpp = max(length(dFdx(uv)), length(dFdy(uv)));
	vec2 q = fract(uv / block) * 2.0 - 1.0;
	float r = length(q);
	// Four leaves: a ring between the centre disc and the block's rim, broken by a cross.
	float hole = step(0.30, r) * step(r, 0.78) * step(0.11, min(abs(q.x), abs(q.y)));
	// Far: dither at the holes' share of the block (about 0.35).
	float far = smoothstep(block * 0.08, block * 0.2, mpp);
	float d = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float cut = mix(hole, step(d, 0.35), far);
	if (cut > 0.5) {
		discard;
	}
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	// The holes' inner faces darken the concrete round them (no geometry for them).
	float rim = (smoothstep(0.18, 0.30, r) * (1.0 - step(0.30, r)) + smoothstep(0.9, 0.78, r) * step(0.78, r)) * (1.0 - far);
	float grain = 1.0 + 0.06 * (h21(floor(uv * 90.0)) - 0.5);
	ALBEDO = cs_out(base * (1.0 - 0.25 * rim) * grain);
	ROUGHNESS = 0.9;
}
