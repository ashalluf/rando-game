// The corner store's products (CornerStoreKit's MultiMeshes: boxes, cans, bottles, bags, packs).
// The mesh is white with what each vertex is in its alpha (CornerStoreKit.P_*: the printed body,
// the label band, a cap or lid, clear plastic over the drink); the instance COLOR (sRGB, it
// multiplies the vertex colour) is the pack's main colour, INSTANCE_CUSTOM.r the second colour's
// hue, .g the design, .b how light the second colour is. UV runs round / across the pack (u) and
// up it (v), 0..1. Works in linear on both renderers.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

varying flat int part;
varying vec3 second;
varying float design;

const int P_BODY = 0;
const int P_LABEL = 1;
const int P_CAP = 2;
const int P_CLEAR = 3;
const int P_SIDE = 4;

vec3 hue(float h) {
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
	return mix(vec3(dot(c, vec3(0.333))), c, 0.8);
}

void vertex() {
	part = int(round(COLOR.a * 8.0));
	second = hue(INSTANCE_CUSTOM.r) * mix(0.25, 1.0, INSTANCE_CUSTOM.b);
	design = INSTANCE_CUSTOM.g;
}

float box_mask(vec2 p, vec2 lo, vec2 hi) {
	vec2 fw = max(fwidth(p), vec2(1e-4));
	vec2 a = smoothstep(lo - fw, lo + fw, p) * (1.0 - smoothstep(hi - fw, hi + fw, p));
	return a.x * a.y;
}

void fragment() {
	vec3 main = cs_srgb_to_linear(COLOR.rgb);
	vec3 sec = second;
	vec2 uv = UV;
	vec3 c = main;
	float rough = 0.42;
	float metal = 0.0;
	// Under a pixel a pack is its average: the print fades as the pack shrinks.
	float fine = 1.0 - smoothstep(0.03, 0.12, max(fwidth(uv.x), fwidth(uv.y)));
	if (part == P_BODY || part == P_LABEL) {
		int d = int(design * 4.0);
		float m = 0.0;
		if (d == 0) {
			m = box_mask(uv, vec2(0.0, 0.32), vec2(1.0, 0.62));
		} else if (d == 1) {
			m = 1.0 - smoothstep(0.2, 0.23, length((uv - vec2(0.5, 0.58)) * vec2(1.0, 1.4)));
		} else if (d == 2) {
			m = box_mask(uv, vec2(0.0, 0.72), vec2(1.0, 0.86)) + box_mask(uv, vec2(0.0, 0.1), vec2(1.0, 0.18));
		} else {
			m = box_mask(uv, vec2(0.12, 0.2), vec2(0.88, 0.78));
		}
		// A white name panel and a few lines of small print.
		float name = box_mask(uv, vec2(0.18, 0.66), vec2(0.82, 0.78)) * step(0.5, fract(design * 7.3));
		float print = box_mask(uv, vec2(0.15, 0.06), vec2(0.85, 0.12)) * step(0.5, fract(uv.x * 14.0));
		c = mix(c, sec, clamp(m, 0.0, 1.0) * mix(0.5, 1.0, fine));
		c = mix(c, vec3(0.86), name * fine);
		c = mix(c, vec3(0.08), print * fine * 0.6);
		rough = part == P_LABEL ? 0.32 : 0.45;
	} else if (part == P_CAP) {
		c = sec * 0.9 + 0.05;
		rough = 0.35;
		metal = 0.3;
	} else if (part == P_CLEAR) {
		// The drink seen through the bottle: the main colour, darker and glossy.
		c = main * 0.55;
		rough = 0.08;
	} else if (part == P_SIDE) {
		c = mix(main, sec, 0.35) * 0.85;
	}
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
}
