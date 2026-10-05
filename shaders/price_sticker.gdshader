shader_type spatial;
// The price on a lot car's windscreen (CarDealers): a quad laid on the glass, one MultiMesh a
// chunk. Two styles in INSTANCE_CUSTOM.g:
//   0  a new car's window card: a white card with a coloured header band, the price in big
//      dark seven-segment-ish figures, small-print lines under it.
//   1  a used car's grease-pencil price, painted straight on the glass in fluorescent yellow
//      or white, with the year underlined above it; no card, everything else cut away.
// INSTANCE_CUSTOM.r is the price seed (0..1), .b the header band's hue pick (0..1).
// UV is 0..1 over the quad (u across the windscreen, v up).
#include "res://shaders/color_space.gdshaderinc"

render_mode cull_back;

varying float v_seed;
varying float v_style;
varying float v_band;

void vertex() {
	v_seed = INSTANCE_CUSTOM.r;
	v_style = INSTANCE_CUSTOM.g;
	v_band = INSTANCE_CUSTOM.b;
}

// Seven segments of a digit in a cell (p in 0..1 x 0..1); `w` stroke width.
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - w;
}

float digit(vec2 p, int n, float w) {
	// Segment layout: a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle.
	int bits[10] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
	int m = bits[clamp(n, 0, 9)];
	float d = 1e3;
	vec2 tl = vec2(0.15, 0.9), tr = vec2(0.85, 0.9), ml = vec2(0.12, 0.5), mr = vec2(0.82, 0.5), bl = vec2(0.1, 0.1), br = vec2(0.8, 0.1);
	if ((m & 1) != 0) d = min(d, seg(p, tl, tr, w));
	if ((m & 2) != 0) d = min(d, seg(p, tr, mr, w));
	if ((m & 4) != 0) d = min(d, seg(p, mr, br, w));
	if ((m & 8) != 0) d = min(d, seg(p, bl, br, w));
	if ((m & 16) != 0) d = min(d, seg(p, ml, bl, w));
	if ((m & 32) != 0) d = min(d, seg(p, tl, ml, w));
	if ((m & 64) != 0) d = min(d, seg(p, ml, mr, w));
	return d;
}

// A string of figures across [x0, x1] at height [y0, y1]; returns the distance.
float figures(vec2 uv, float x0, float x1, float y0, float y1, int count, int value, float w) {
	float cw = (x1 - x0) / float(count);
	if (uv.x < x0 || uv.x > x1 || uv.y < y0 || uv.y > y1) {
		return 1e3;
	}
	int k = int(floor((uv.x - x0) / cw));
	vec2 p = vec2((uv.x - x0 - float(k) * cw) / cw, (uv.y - y0) / (y1 - y0));
	int place = count - 1 - k;
	int dgt = (value / int(pow(10.0, float(place)) + 0.5)) % 10;
	// Slant the figures a little, like a hand or a print face.
	p.x -= (p.y - 0.5) * 0.12;
	return digit(p, dgt, w);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float aa = 0.012;
	if (v_style < 0.5) {
		// A dealer's window card.
		int price = 18000 + int(floor(v_seed * 34.0)) * 1000 + 995;
		vec3 card = vec3(0.96, 0.96, 0.94);
		vec3 bands[4] = vec3[](vec3(0.75, 0.06, 0.05), vec3(0.08, 0.25, 0.7), vec3(0.06, 0.45, 0.2), vec3(0.95, 0.55, 0.05));
		vec3 band = bands[int(floor(v_band * 3.99))];
		vec3 col = card;
		if (uv.y > 0.78) {
			col = band;
		}
		float d = figures(uv, 0.1, 0.92, 0.38, 0.7, 5, price, 0.07);
		// A dollar sign's stand-in: a short bar before the figures.
		d = min(d, seg(uv, vec2(0.05, 0.42), vec2(0.05, 0.66), 0.012));
		float ink = 1.0 - smoothstep(-aa, aa, d * 0.15);
		col = mix(col, vec3(0.04), ink);
		// Small print.
		float lines = step(0.5, fract(uv.y * 24.0)) * step(uv.y, 0.3) * step(0.08, uv.y) * step(0.08, uv.x) * step(uv.x, 0.92 - 0.3 * fract(floor(uv.y * 24.0) * 0.37));
		col = mix(col, vec3(0.35), lines * 0.6);
		ALBEDO = cs_out(cs_srgb_to_linear(col));
		ROUGHNESS = 0.7;
		SPECULAR = 0.25;
	} else {
		// Grease pencil on the glass.
		int price = 2995 + int(floor(v_seed * 90.0)) * 100;
		int year = 2004 + int(floor(fract(v_seed * 13.7) * 18.0));
		float d = figures(uv, 0.08, 0.92, 0.12, 0.58, 4, price, 0.085);
		d = min(d, figures(uv, 0.28, 0.72, 0.68, 0.9, 4, year, 0.07));
		d = min(d, seg(uv, vec2(0.25, 0.64), vec2(0.75, 0.64), 0.012));
		float ink = 1.0 - smoothstep(-aa, aa, d * 0.15);
		if (ink < 0.5) {
			discard;
		}
		vec3 pens[2] = vec3[](vec3(0.98, 0.92, 0.1), vec3(0.97, 0.97, 0.95));
		vec3 col = pens[int(step(0.6, fract(v_seed * 7.3)))];
		ALBEDO = cs_out(cs_srgb_to_linear(col));
		ROUGHNESS = 0.55;
		EMISSION = cs_out(cs_srgb_to_linear(col) * 0.08);
	}
}
