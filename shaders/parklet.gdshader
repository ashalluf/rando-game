shader_type spatial;
render_mode cull_back;

// Outdoor dining parklets (scripts/world/parklets.gd, ParkletKit): the timber deck out in the
// parking lane, its planters, screens and delineators, the bistro tables and chairs, the canvas
// umbrellas and the festoon of bulbs strung over it. One material for all of it, so each kind of
// piece is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (ParkletKit.A_*, round(a * 20)): 0 the vertex colour
//   is the colour, 1 the instance's paint (INSTANCE_CUSTOM.rgb); in between decking, timber,
//   canvas, powder-coated steel, bulbs, glass, china, food, soil, marble, rattan, reflective
//   sheeting, a candle's flame and the light string's cable. The codes sit 0.05 apart so 8-bit
//   vertex colours keep them.
// * UV2 is (roughness, metallic) per part. UV is metres (StreetClutter's projection).
// * INSTANCE_CUSTOM.a: 0.5 and over, the restaurant is open and its lights burn after dark; the
//   fraction under it seeds the weathering.
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// The festoon bulbs at full night, and how much of it shows by day (a dim filament in shade).
uniform float bulb_night = 7.5;
uniform float bulb_day = 0.25;
// The candle in its glass on each table after dark.
uniform float candle_night = 3.5;
// The delineators' sheeting: how bright it glints after dark (the headlights).
uniform float reflect_night = 1.6;
// Decking: board width (m) and how dark the gaps between boards are.
uniform float board_width = 0.14;
uniform float gap_dark = 0.25;
// How grey the timber has weathered (0 oiled, 1 silver).
uniform float weathering = 0.3;

varying vec3 v_local;
varying float v_mode;
varying vec3 v_paint;
varying float v_seed;
varying float v_lit;

float pk_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float pk_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pk_hash(i), pk_hash(i + vec2(1.0, 0.0)), f.x),
		mix(pk_hash(i + vec2(0.0, 1.0)), pk_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_mode = COLOR.a;
	v_paint = INSTANCE_CUSTOM.rgb;
	v_lit = step(0.5, INSTANCE_CUSTOM.a);
	v_seed = fract(INSTANCE_CUSTOM.a * 2.0);
}

// Wood along `along` (metres), across `across`: grain streaks, growth rings, a tone per board.
vec3 pk_wood(vec3 base, float along, float across, float board, float px) {
	float tone = 0.82 + 0.3 * pk_hash(vec2(board, v_seed * 17.0));
	float fine = clamp(1.0 - px * 40.0, 0.0, 1.0);
	float grain = pk_noise(vec2(along * 2.2 + board * 7.3, across * 55.0 + board));
	float rings = sin(across * 140.0 + pk_noise(vec2(along * 0.8, board)) * 9.0) * 0.5 + 0.5;
	vec3 c = base * tone * (0.88 + 0.2 * mix(0.5, grain, fine)) * (0.95 + 0.08 * mix(0.5, rings, fine));
	// Weathered timber goes silver where the sun and feet have had it.
	float grey = dot(c, vec3(0.3, 0.55, 0.15)) * 1.15;
	return mix(c, vec3(grey), weathering * (0.6 + 0.4 * pk_noise(vec2(along * 0.4, board + 3.0))));
}

void fragment() {
	int code = int(round(v_mode * 20.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	float px = length(fwidth(v_local));
	if (code == 20) {
		base = cs_srgb_to_linear(v_paint);
		base *= 0.95 + 0.06 * pk_noise(UV * 6.0 + v_seed * 31.0);
	} else if (code == 2) {
		// Decking: boards running along the kerb (local x), gaps between them, butt joints
		// staggered board to board, a fastener pair at each joist.
		float across = v_local.z / board_width;
		float board = floor(across);
		float f = fract(across);
		float gap_w = 0.006 / board_width;
		float gap = 1.0 - smoothstep(0.0, gap_w + px / board_width, min(f, 1.0 - f));
		float off = pk_hash(vec2(board, 2.3)) * 2.4;
		float seg = floor((v_local.x + off) / 2.4);
		float jx = fract((v_local.x + off) / 2.4) * 2.4;
		float butt = 1.0 - smoothstep(0.0, 0.004 + px, min(jx, 2.4 - jx));
		base = pk_wood(base, v_local.x, v_local.z, board * 13.0 + seg, px);
		// Screws over the joists every 0.4 m, two a board.
		vec2 sp = vec2(fract(v_local.x / 0.4) * 0.4 - 0.2, (f - 0.5) * board_width);
		float screw = 1.0 - smoothstep(0.004, 0.006 + px, min(length(sp - vec2(0.0, 0.035)), length(sp + vec2(0.0, 0.035))));
		base *= 1.0 - 0.45 * screw * clamp(1.0 - px * 60.0, 0.0, 1.0);
		// Scuffed paler down the middle where chairs drag and feet go.
		float wear = smoothstep(0.6, 1.0, pk_noise(v_local.xz * 1.3 + v_seed * 9.0));
		base = mix(base, base * 1.18 + 0.02, wear * 0.4);
		base *= 1.0 - (1.0 - gap_dark) * max(gap, butt);
		rough = mix(0.72, 0.95, max(gap, butt));
		// A wet deck darkens and shines a little.
		float wet = clamp(road_wetness, 0.0, 1.0);
		base *= 1.0 - 0.35 * wet;
		rough = mix(rough, 0.35, wet * 0.8);
	} else if (code == 3) {
		// Timber (slats, planters, posts): grain along the piece's longest run in its UV.
		float a = UV.x;
		float b = UV.y;
		base = pk_wood(base, a, b, floor(b / 0.09) + floor(v_local.y * 3.0) * 7.0, px);
		rough = 0.78;
	} else if (code == 4) {
		// Umbrella canvas: the instance's colour, a woven tooth, sun-faded on top, a little
		// translucent from below.
		base = cs_srgb_to_linear(v_paint);
		float weave = pk_noise(UV * 160.0);
		base *= 0.92 + 0.12 * mix(0.5, weave, clamp(1.0 - px * 80.0, 0.0, 1.0));
		base = mix(base, vec3(dot(base, vec3(0.33))) * 1.1, 0.1 * smoothstep(2.0, 2.4, v_local.y));
		rough = 0.88;
	} else if (code == 5) {
		// Powder-coated steel (table bases, posts, the delineators' feet): a fine orange peel.
		base *= 0.92 + 0.08 * pk_noise(UV * 30.0 + v_seed * 5.0);
	} else if (code == 6) {
		// A festoon bulb: warm glass, the filament lit when the restaurant is open after dark.
		emit = vec3(1.0, 0.62, 0.28) * mix(bulb_day, bulb_night, lamp) * v_lit;
		base = vec3(0.9, 0.82, 0.7);
		rough = 0.12;
	} else if (code == 7) {
		rough = 0.05;
		metal = 0.0;
	} else if (code == 9) {
		// Food on the plate: a broken tone so a heap is not one flat colour.
		base *= 0.75 + 0.45 * pk_noise(v_local.xz * 41.0 + v_local.y * 13.0);
	} else if (code == 10) {
		// A clipped hedge (boxwood): clusters of small glossy leaves, lighter tips in the sun,
		// dark hollows between the clusters and down at the soil.
		vec2 lp = v_local.xz * 64.0 + v_local.y * 41.0;
		float n1 = pk_noise(lp + v_seed * 7.0);
		float n2 = pk_noise(lp * 2.3 + 11.0);
		float fine = clamp(1.0 - px * 90.0, 0.0, 1.0);
		float leaf = mix(0.5, n1 * 0.6 + n2 * 0.4, fine);
		base *= 0.55 + 0.75 * leaf;
		base = mix(base, base * vec3(1.15, 1.2, 0.8), smoothstep(0.65, 0.9, n2) * fine);
		float low = smoothstep(0.64, 0.95, v_local.y);
		base *= 0.55 + 0.45 * low;
		NORMAL_MAP = vec3(0.5 + (n1 - 0.5) * 0.9 * fine, 0.5 + (n2 - 0.5) * 0.9 * fine, 1.0);
		rough = mix(0.75, 0.5, leaf);
	} else if (code == 11) {
		// Planter soil and bark mulch.
		float n = pk_noise(v_local.xz * 26.0);
		base *= 0.6 + 0.6 * n;
		rough = 0.95;
	} else if (code == 12) {
		// Marble table tops: pale stone with soft grey veins.
		float v = pk_noise(v_local.xz * 4.0 + v_seed * 3.0) * 2.0 + v_local.x * 3.0;
		float vein = 1.0 - smoothstep(0.0, 0.05 + px * 4.0, abs(fract(v) - 0.5));
		base *= 1.0 - 0.18 * vein * pk_noise(v_local.xz * 9.0);
		rough = 0.22;
	} else if (code == 13) {
		// Rattan weave on the bistro chairs: a two-colour basket weave, faded under a pixel.
		vec2 w = UV * 70.0;
		float cell = mod(floor(w.x) + floor(w.y), 2.0);
		float band = cell < 0.5 ? fract(w.x) : fract(w.y);
		float strand = smoothstep(0.0, 0.3, band) * smoothstep(1.0, 0.7, band);
		float fine = clamp(1.0 - px * 90.0, 0.0, 1.0);
		vec3 c2 = cs_srgb_to_linear(v_paint);
		base = mix(base, mix(base, c2, cell), 0.6 * fine + 0.25 * (1.0 - fine));
		base *= mix(0.85, 0.65 + 0.4 * strand, fine);
		rough = 0.7;
	} else if (code == 14) {
		// Retroreflective sheeting: plain white by day, glinting back at the lights after dark.
		emit = base * reflect_night * lamp * 0.5;
		rough = 0.4;
	} else if (code == 15) {
		// A candle's flame and the glow in its glass.
		emit = vec3(1.0, 0.55, 0.18) * candle_night * lamp * v_lit;
		base = vec3(0.95, 0.9, 0.8);
	}
	// Road grime up the deck's fascia and the planters' feet (local y from the road).
	if (code != 6 && code != 15 && code != 4 && code != 14) {
		float gh = clamp(1.0 - v_local.y / 0.3, 0.0, 1.0);
		float n = pk_noise(v_local.xz * 4.0 + v_local.y * 3.0 + v_seed * 13.0);
		base *= 1.0 - 0.3 * gh * (0.5 + 0.5 * n);
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (code == 4) {
		BACKLIGHT = cs_out(base * 0.45);
	}
}
