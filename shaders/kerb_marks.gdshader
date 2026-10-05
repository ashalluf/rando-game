shader_type spatial;
render_mode cull_back;

// The kerb's marks (scripts/world/kerbs.gd): painted kerb zones, truncated-dome pads, house-number
// plates and stencilled lettering, the dirt in bare tree wells, the cast-iron tree grates (the
// tree_grate batch) and hairline cracks. One material, so a 64 m tile of kerb is one draw.
//
// * COLOR.a is the kind (Kerbs.Kind: kind / 16 + half a step); COLOR.rgb the paint or ink, sRGB
//   (vertex colours arrive raw on both renderers; decoded here, worked in linear, handed back
//   through cs_out()).
// * UV is metres in the mark's own frame (a zone: along the kerb, then up the face and over its
//   top edge, one coordinate round the corner; a pad: across and up the ramp; a glyph: 0..1 over
//   its cell). UV2 is data: a zone's seed; a glyph's 5 x 7 bitmap (rows 0-3 in x, 4-6 in y, five
//   bits a row, exact in a float); a crack's seed and width.
// * Anything finer than a pixel fades to its average (domes, grate slots, stencil strokes, wear
//   speckle), or it shimmers.

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

uniform float wear = 0.55;
uniform float dome_pitch = 0.06;
uniform float dome_base = 0.0175;
uniform float dome_top = 0.0095;

varying vec3 v_world;
varying float v_kind;

float km_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float km_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(km_hash(i), km_hash(i + vec2(1.0, 0.0)), f.x),
		mix(km_hash(i + vec2(0.0, 1.0)), km_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float km_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * km_noise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

// Whether glyph cell (c, r) (column 0-4 from the left, row 0-6 from the top) is inked.
bool km_bit(int lo, int hi, int c, int r) {
	if (c < 0 || c > 4 || r < 0 || r > 6) {
		return false;
	}
	int row = r < 4 ? (lo >> (5 * r)) & 31 : (hi >> (5 * (r - 4))) & 31;
	return ((row >> (4 - c)) & 1) == 1;
}

float km_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_kind = floor(COLOR.a * 16.0);
}

void fragment() {
	int kind = int(v_kind + 0.5);
	vec3 paint = cs_srgb_to_linear(COLOR.rgb);
	vec3 base = paint;
	float rough = 0.78;
	float ao = 1.0;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float px = max(fwidth(UV.x), fwidth(UV.y));
	vec2 wp = v_world.xz;

	if (kind == 0) {
		// A painted zone: two coats, the top one worn through to the older one and both to the
		// concrete; sun-faded, scuffed by tyres low on the face and by feet on the top edge.
		float seed = UV2.x * 71.0;
		vec2 q = vec2(UV.x, UV.y) * vec2(9.0, 24.0) + seed;
		float n = km_fbm(q);
		float fine = km_noise(UV * vec2(60.0, 90.0) + seed) * (1.0 - smoothstep(0.004, 0.012, px));
		float edge_top = smoothstep(0.03, 0.0, abs(UV.y - 0.15));
		float low = smoothstep(0.05, 0.0, UV.y);
		float scuff = wear * (0.30 + 0.45 * edge_top + 0.35 * low);
		float worn_top = step(n + 0.12 * fine, scuff);
		float worn_all = step(n * 0.9 + 0.15 * fine + 0.05, scuff * 0.55);
		if (worn_all > 0.5) {
			discard;
		}
		// Sun-faded: a little lighter and greyer, unevenly (it read as pink at 0.35-0.65).
		vec3 faded = mix(paint, mix(paint, vec3(dot(paint, vec3(0.3333))), 0.5) * 1.25, 0.12 + 0.22 * km_noise(UV * 0.6 + seed));
		vec3 old = mix(paint * 0.7, vec3(0.20, 0.19, 0.18), 0.35);
		base = mix(faded, old, worn_top);
		// Grime from the gutter, tyre rubber along the face.
		float grime = (1.0 - smoothstep(0.0, 0.09, UV.y)) * (0.35 + 0.4 * km_noise(vec2(UV.x * 3.0, seed)));
		float rubber = smoothstep(0.6, 0.85, km_noise(vec2(UV.x * 0.9 + seed, 3.0))) * smoothstep(0.11, 0.03, UV.y) * step(UV.y, 0.15);
		base *= (1.0 - 0.45 * grime) * (1.0 - 0.6 * rubber);
		base *= 0.9 + 0.2 * km_noise(UV * vec2(2.0, 8.0) + seed * 3.0);
		rough = 0.72 + 0.15 * worn_top;
	} else if (kind == 1) {
		// Truncated domes: a square grid of short flat-topped domes, yellow, dirt in the valleys,
		// tops polished paler by shoes.
		vec2 g = UV / dome_pitch;
		vec2 f = fract(g) - 0.5;
		float r = length(f) * dome_pitch;
		float h = clamp((dome_base - r) / (dome_base - dome_top), 0.0, 1.0);
		float detail = 1.0 - smoothstep(dome_pitch * 0.25, dome_pitch * 0.6, px);
		vec2 slope = (r > dome_top && r < dome_base) ? normalize(f + 1e-5) * 0.55 : vec2(0.0);
		nmap = vec3(0.5 + 0.5 * slope.x * detail, 0.5 + 0.5 * slope.y * detail, 1.0);
		float valley = 1.0 - h;
		float dirt = km_fbm(wp * 3.0) * 0.6 + 0.4;
		vec3 yellow = paint * (0.9 + 0.15 * km_noise(UV * 5.0 + UV2.x * 40.0));
		base = mix(yellow, yellow * vec3(0.55, 0.5, 0.45), valley * dirt * 0.6 * detail + 0.12 * (1.0 - detail));
		base = mix(base, base * 1.12 + vec3(0.03), smoothstep(0.95, 1.0, h) * 0.5 * detail);
		ao = mix(1.0, 0.75, valley * detail);
		rough = 0.6 + 0.2 * valley;
	} else if (kind == 2) {
		// A house-number plate: white, sprayed through a mask (soft, a little overspray), worn.
		float seed = UV2.x * 53.0;
		float n = km_fbm(UV * vec2(28.0, 40.0) + seed);
		if (n < wear * 0.32) {
			discard;
		}
		base = paint * (0.85 + 0.12 * km_noise(UV * 9.0 + seed));
		base *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.03, UV.y)) * km_noise(UV * vec2(4.0, 1.0));
		rough = 0.7;
	} else if (kind == 3) {
		// Stencil lettering: the 5 x 7 face as rounded strokes joining neighbouring dots, with the
		// soft edge of a spray can. Under a pixel the strokes fade to the ink's coverage.
		int lo = int(UV2.x + 0.5);
		int hi = int(UV2.y + 0.5);
		vec2 cell = vec2(UV.x * 5.0, (1.0 - UV.y) * 7.0);
		ivec2 ci = ivec2(floor(cell));
		float d = 9.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				int c = ci.x + dx;
				int r = ci.y + dy;
				if (!km_bit(lo, hi, c, r)) {
					continue;
				}
				vec2 p = vec2(float(c), float(r)) + 0.5;
				d = min(d, length(cell - p));
				if (km_bit(lo, hi, c + 1, r)) {
					d = min(d, km_seg(cell, p, p + vec2(1.0, 0.0)));
				}
				if (km_bit(lo, hi, c, r + 1)) {
					d = min(d, km_seg(cell, p, p + vec2(0.0, 1.0)));
				}
				if (km_bit(lo, hi, c + 1, r + 1) && !km_bit(lo, hi, c + 1, r) && !km_bit(lo, hi, c, r + 1)) {
					d = min(d, km_seg(cell, p, p + vec2(1.0, 1.0)));
				}
				if (km_bit(lo, hi, c - 1, r + 1) && !km_bit(lo, hi, c - 1, r) && !km_bit(lo, hi, c, r + 1)) {
					d = min(d, km_seg(cell, p, p + vec2(-1.0, 1.0)));
				}
			}
		}
		float cpx = max(fwidth(cell.x), fwidth(cell.y));
		float stroke = 0.42 + 0.06 * (km_noise(cell * 3.0 + wp * 7.0) - 0.5);
		float ink = 1.0 - smoothstep(stroke - max(0.12, cpx), stroke + max(0.12, cpx), d);
		ink *= step(0.18, km_fbm(cell * 1.7 + wp * 3.0) + 0.25);
		if (ink < 0.5) {
			discard;
		}
		base = paint * (0.9 + 0.1 * km_noise(cell * 2.0));
		rough = 0.75;
	} else if (kind == 4) {
		// A bare dirt tree well: packed dirt, mulch chips, a few dead leaves; darker toward its
		// walls.
		float n = km_fbm(UV * 6.0 + UV2.x * 30.0);
		float chips = km_noise(UV * 38.0 + UV2.x * 11.0) * (1.0 - smoothstep(0.004, 0.01, px));
		vec3 dirt = vec3(0.045, 0.033, 0.024) * (0.75 + 0.5 * n);
		vec3 mulch = vec3(0.075, 0.048, 0.03);
		base = mix(dirt, mulch, smoothstep(0.6, 0.85, chips) * 0.6);
		float leaf = smoothstep(0.84, 0.92, km_noise(UV * 9.0 + 40.0)) * (1.0 - smoothstep(0.006, 0.02, px));
		base = mix(base, vec3(0.11, 0.075, 0.035), leaf * 0.6);
		float half_size = UV2.y * 0.5;
		float edge = half_size - max(abs(UV.x), abs(UV.y));
		ao = mix(0.55, 1.0, smoothstep(0.0, 0.12, edge));
		nmap = vec3(0.5 + 0.25 * (km_noise(UV * 30.0) - 0.5), 0.5 + 0.25 * (km_noise(UV * 30.0 + 7.0) - 0.5), 1.0);
		rough = 0.95;
	} else if (kind == 5) {
		// A cast-iron tree grate: a frame, rings of radial slots round the trunk's opening, cast
		// studs in the corners. Rust in the slots, the bars polished by feet.
		vec2 p = UV;
		float r = length(p);
		float a = atan(p.y, p.x);
		float detail = 1.0 - smoothstep(0.008, 0.02, px);
		float frame = step(0.75, max(abs(p.x), abs(p.y)));
		float hole = 1.0 - step(0.3, r);
		float ring = (r - 0.34) / 0.065;
		float k = floor(ring);
		float in_ring = step(0.0, ring) * step(k, 5.0) * (1.0 - frame);
		float segs = floor(10.0 + k * 5.0);
		float fa = fract(a / 6.2831853 * segs + k * 0.37);
		float slot_r = smoothstep(0.18, 0.26, fract(ring)) * smoothstep(0.82, 0.74, fract(ring));
		float slot_a = smoothstep(0.08, 0.16, fa) * smoothstep(0.92, 0.84, fa);
		float slot = in_ring * slot_r * slot_a * step(r, 0.75);
		float stud = (1.0 - in_ring) * (1.0 - frame) * (1.0 - hole) * step(0.75, r)
			* (1.0 - smoothstep(0.012, 0.02, length(fract(p / 0.05) - 0.5) * 0.05));
		vec3 iron = vec3(0.045, 0.040, 0.036) * (0.8 + 0.5 * km_fbm(wp * 9.0));
		vec3 rust = vec3(0.13, 0.06, 0.03);
		iron = mix(iron, rust, smoothstep(0.55, 0.85, km_fbm(wp * 4.0 + 3.0)) * 0.6);
		float polish = (1.0 - slot) * smoothstep(0.4, 0.8, km_noise(wp * 2.0)) * 0.35;
		vec3 below = vec3(0.012, 0.009, 0.007);
		vec3 surf = mix(iron * (1.0 + polish * 1.5), below, slot * detail);
		surf = mix(surf, vec3(0.06, 0.042, 0.03), hole);
		// Past the slots' size, their share of dark.
		float share = 0.33;
		base = mix(mix(iron, below, share * (1.0 - frame) * (1.0 - hole) * step(r, 0.75)), surf, detail);
		base *= 1.0 + 0.4 * stud * detail;
		nmap = vec3(0.5 + 0.2 * stud * detail, 0.5, 1.0);
		ao = mix(1.0, 0.6, slot * detail);
		rough = mix(0.62, 0.95, slot);
		rough = mix(rough, 0.45, polish);
	} else {
		// A hairline crack: a jagged dark line, its edges chipped. Held at a pixel wide at range
		// and faded by the coverage it would really have.
		float seed = UV2.x * 91.0;
		float w = max(UV2.y, 1e-3);
		float off = (km_fbm(vec2(UV.x * 6.0 + seed, seed)) - 0.5) * 0.55 + (km_noise(vec2(UV.x * 40.0, seed)) - 0.5) * 0.12;
		float dm = abs(UV.y - 0.5 - off) * w;
		float taper = smoothstep(0.0, 0.15, UV.x);
		float hw = (0.0018 + 0.0022 * km_noise(vec2(UV.x * 9.0, seed))) * taper;
		float mpx = px * w;
		float cover = clamp(hw / max(mpx * 0.6, 1e-5), 0.0, 1.0);
		if (dm > max(hw, mpx * 0.6) || mpx > 0.04) {
			discard;
		}
		base = mix(vec3(0.16, 0.15, 0.14), paint, cover);
		rough = 0.95;
	}

	// Wet: darker and glossier, with the street.
	float wet = clamp(road_wetness, 0.0, 1.0);
	base *= 1.0 - 0.3 * wet;
	rough = mix(rough, 0.15, wet * 0.85);

	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = nmap;
}
