// The corner store's products (CornerStoreKit's MultiMeshes: boxes, cans, bottles, bags, packs).
// The mesh is white with what each vertex is in its alpha (CornerStoreKit.P_*: the printed front,
// a label band, a cap or lid, clear plastic over the drink, a side). The print is a cell of the
// packaging atlas (tools/walk_in_store/make_goods_atlas.py: 8 x 8 invented packs) picked by
// INSTANCE_CUSTOM.r (cell / 64); .b is a fade (sun, age), .g a crinkle phase for bags. The instance
// COLOR (sRGB, it multiplies the vertex colour) is the drink's colour behind clear plastic and the
// caps' paint. UV runs across the pack (u) and up it (v), 0..1. Linear on both renderers.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D labels : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

varying flat int part;
varying vec2 cell0;
varying float fade;

const int P_BODY = 0;
const int P_LABEL = 1;
const int P_CAP = 2;
const int P_CLEAR = 3;
const int P_SIDE = 4;

void vertex() {
	part = int(round(COLOR.a * 8.0));
	float c = floor(INSTANCE_CUSTOM.r * 64.0 + 0.5);
	cell0 = vec2(mod(c, 8.0), floor(c / 8.0)) / 8.0;
	fade = INSTANCE_CUSTOM.b;
}

vec3 print_at(vec2 uv) {
	// Inset by a texel or two so the mips never reach the next cell.
	vec2 q = clamp(uv, vec2(0.012), vec2(0.988));
	return cs_in(texture(labels, cell0 + vec2(q.x, 1.0 - q.y) / 8.0).rgb);
}

void fragment() {
	vec3 tint = cs_srgb_to_linear(COLOR.rgb);
	vec2 uv = UV;
	vec3 c;
	float rough = 0.45;
	float metal = 0.0;
	if (part == P_BODY) {
		c = print_at(fract(uv));
	} else if (part == P_LABEL) {
		// Round packs wrap the label: u runs 0..2 round, so the print repeats on the back.
		c = print_at(vec2(fract(uv.x), uv.y));
		rough = 0.32;
	} else if (part == P_SIDE) {
		// A box's side: the print's ground carried round, with a strip of small print.
		c = print_at(vec2(0.04, uv.y));
		c *= 0.82;
	} else if (part == P_CAP) {
		c = mix(tint, print_at(vec2(0.5, 0.92)), 0.35) * 0.85;
		rough = 0.3;
		metal = 0.25;
	} else {
		// The drink through the bottle: its own colour, darker and glossy.
		c = tint * 0.5;
		rough = 0.06;
	}
	// Faded packs at the front of a sunny shelf.
	c = mix(c, vec3(dot(c, vec3(0.33))) * 1.08, fade * 0.35);
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
}
