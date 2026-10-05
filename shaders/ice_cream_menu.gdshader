shader_type spatial;
// The ice-cream truck's menu boards (mode 0) and striped awning (mode 1), drawn from where the
// fragment sits on the model (no UVs on the car bodies): boards on the sides read (z, y), the back
// (x, y). A board is a grid of picture tiles - cones, ice lollies, sundaes, sandwich bars, rocket
// pops, two-scoop cones - each on its own pastel ground with a price roundel in the truck's accent
// colour. Original pictures, no lettering, no brands. `accent` is set from script as a Vector3 of
// the trim colour's raw (sRGB) numbers. Works in linear (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 accent = vec3(0.88, 0.32, 0.52);
uniform int mode = 0;

varying vec3 lp;
varying vec3 ln;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float circle(vec2 p, float r) {
	return length(p) - r;
}

// A cone pointing down: tip at (0, -h), mouth of half width w at y = 0.
float cone_sdf(vec2 p, float w, float h) {
	vec2 q = vec2(abs(p.x), p.y + h);
	float side = (q.x * h - q.y * w) / length(vec2(h, w));
	return max(side, p.y);
}

float fill(float d, float px) {
	return 1.0 - smoothstep(-px, px, d);
}

vec3 pastel(float k) {
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (k + vec3(0.0, 0.33, 0.67)));
	return mix(c, vec3(1.0), 0.45);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 acc = cs_srgb_to_linear(accent);
	if (mode == 1) {
		// Awning canvas: stripes across it, the accent and an off-white, sun-faded, a little dirt.
		float s = step(0.5, fract(lp.z / 0.24));
		vec3 col = mix(cs_srgb_to_linear(vec3(0.94, 0.93, 0.88)), acc, s);
		col *= 0.88 + 0.12 * h21(floor(lp.zx * 30.0));
		ALBEDO = cs_out(col);
		ROUGHNESS = 0.85;
		SPECULAR = 0.25;
	} else {
		vec2 uv = abs(ln.x) > 0.5 ? vec2(lp.z * sign(ln.x), lp.y) : vec2(-lp.x, lp.y);
		vec2 cell = vec2(0.38, 0.42);
		vec2 id = floor(uv / cell);
		vec2 p = (fract(uv / cell) - 0.5) * cell;
		float px = max(fwidth(uv.x), fwidth(uv.y)) * 1.2;
		float r = h21(id);
		float pick = floor(h21(id + 7.3) * 6.0);
		vec3 col = cs_srgb_to_linear(vec3(0.95, 0.93, 0.86));
		// The tile and its ground.
		float tile = fill(box(p, cell * 0.5 - 0.022, 0.03), px);
		vec3 ground = cs_srgb_to_linear(pastel(r));
		col = mix(col, ground, tile);
		vec2 q = p - vec2(0.0, 0.025);
		vec3 wafer = cs_srgb_to_linear(vec3(0.78, 0.55, 0.26));
		vec3 cream = cs_srgb_to_linear(vec3(0.98, 0.95, 0.86));
		vec3 ice = cs_srgb_to_linear(pastel(r + 0.5) * vec3(1.0, 0.9, 0.95));
		vec3 choc = cs_srgb_to_linear(vec3(0.30, 0.16, 0.08));
		if (pick < 1.0) {
			col = mix(col, wafer, fill(cone_sdf(q - vec2(0.0, 0.0), 0.075, 0.14), px) * tile);
			col = mix(col, ice, fill(circle(q - vec2(0.0, 0.045), 0.075), px) * tile);
		} else if (pick < 2.0) {
			col = mix(col, wafer, fill(box(q - vec2(0.0, -0.10), vec2(0.012, 0.05), 0.006), px) * tile);
			col = mix(col, ice, fill(box(q - vec2(0.0, 0.03), vec2(0.055, 0.10), 0.04), px) * tile);
		} else if (pick < 3.0) {
			col = mix(col, cream, fill(circle(q - vec2(0.0, 0.03), 0.07), px) * tile);
			col = mix(col, cs_srgb_to_linear(vec3(0.85, 0.05, 0.10)), fill(circle(q - vec2(0.02, 0.11), 0.018), px) * tile);
			col = mix(col, cs_srgb_to_linear(vec3(0.75, 0.85, 0.95)), fill(box(q - vec2(0.0, -0.06), vec2(0.08, 0.05), 0.02), px) * tile);
		} else if (pick < 4.0) {
			float bar = fill(box(q, vec2(0.10, 0.055), 0.02), px);
			col = mix(col, choc, bar * tile);
			col = mix(col, cream, fill(box(q, vec2(0.10, 0.018), 0.005), px) * tile);
		} else if (pick < 5.0) {
			vec2 rq = q - vec2(0.0, 0.0);
			float body = fill(box(rq, vec2(0.045, 0.10), 0.03), px);
			vec3 rocket = rq.y > 0.035 ? cs_srgb_to_linear(vec3(0.85, 0.10, 0.12)) : (rq.y > -0.035 ? cream : cs_srgb_to_linear(vec3(0.12, 0.30, 0.80)));
			col = mix(col, rocket, body * tile);
			col = mix(col, wafer, fill(box(q - vec2(0.0, -0.13), vec2(0.010, 0.04), 0.005), px) * tile);
		} else {
			col = mix(col, wafer, fill(cone_sdf(q - vec2(0.0, -0.03), 0.07, 0.12), px) * tile);
			col = mix(col, ice, fill(circle(q - vec2(0.0, 0.01), 0.065), px) * tile);
			col = mix(col, cream, fill(circle(q - vec2(0.0, 0.10), 0.058), px) * tile);
		}
		// The price roundel and its dots (no numerals).
		vec2 pr = p - vec2(cell.x * 0.30, -cell.y * 0.32);
		col = mix(col, acc, fill(circle(pr, 0.038), px) * tile);
		col = mix(col, vec3(0.95), fill(box(pr, vec2(0.022, 0.006), 0.003), px) * tile);
		// The board's gloss print and a little road grime low down.
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.8, 1.4, lp.y));
		ALBEDO = cs_out(col);
		ROUGHNESS = 0.32;
		SPECULAR = 0.5;
	}
}
