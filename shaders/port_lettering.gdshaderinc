// The terminal's lettering (container.gdshader, port_steel.gdshader): a bold, chamfered stroke
// font as segments in a distance field, the invented shipping lines' names and owner codes, and
// their marks. Livery indices are PortKit.LIVERY_PAINT's. Every name and mark is invented - none
// is a real shipping line. Needs nothing from the including shader.

// Mark per livery: 0 wave in a disc, 1 diamond with a dot, 2 chevrons, 3 sail, 4 rings, 5 sun,
// -1 none.
const int MARK[9] = int[](0, 1, 2, 3, 4, 5, -1, -1, -1);
const int NAME_AT[9] = int[](0, 6, 12, 18, 24, 30, -1, -1, -1);
const int NAME_LEN[9] = int[](5, 6, 6, 5, 6, 6, 0, 0, 0);
const int OWNER_AT[9] = int[](36, 40, 44, 48, 52, 56, 60, 64, 68);

// Glyphs: 0 A, 1 D, 2 E, 3 I, 4 K, 5 L, 6 M, 7 N, 8 O, 9 P, 10 R, 11 T, 12 U, 13 V, 14 Z, 15 G,
// 16..25 the digits 0..9. Names: RANDO KAVELL TORVAN ZEPRA OLVANA MERIDU (6 slots each), then
// the owner codes (4 each): RNDU KVLU TRVU ZPRU OLVU MRDU AMLU DKTU PAZU.
const int TEXT[72] = int[](
	10, 0, 7, 1, 8, -1,
	4, 0, 13, 2, 5, 5,
	11, 8, 10, 13, 0, 7,
	14, 2, 9, 10, 0, -1,
	8, 5, 13, 0, 7, 0,
	6, 2, 10, 3, 1, 12,
	10, 7, 1, 12,
	4, 13, 5, 12,
	11, 10, 13, 12,
	14, 9, 10, 12,
	8, 5, 13, 12,
	6, 10, 1, 12,
	0, 6, 5, 12,
	1, 4, 11, 12,
	9, 0, 14, 12);

// Stroke font on a 4 x 6 grid (x right, y up): each glyph is G_COUNT segments from G_START.
const int G_START[26] = int[](0, 6, 12, 16, 19, 22, 24, 28, 31, 39, 45, 52, 54, 59, 61, 64, 73, 81, 84, 90, 98, 101, 108, 117, 119, 124);
const int G_COUNT[26] = int[](6, 6, 4, 3, 3, 2, 4, 3, 8, 6, 7, 2, 5, 2, 3, 9, 8, 3, 6, 8, 3, 7, 9, 2, 5, 9);
const vec4 SEG[133] = vec4[](
	// A
	vec4(0.0, 0.0, 0.0, 4.5), vec4(0.0, 4.5, 1.4, 6.0), vec4(1.4, 6.0, 2.6, 6.0), vec4(2.6, 6.0, 4.0, 4.5), vec4(4.0, 4.5, 4.0, 0.0), vec4(0.0, 2.6, 4.0, 2.6),
	// D
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 2.6, 6.0), vec4(2.6, 6.0, 4.0, 4.6), vec4(4.0, 4.6, 4.0, 1.4), vec4(4.0, 1.4, 2.6, 0.0), vec4(2.6, 0.0, 0.0, 0.0),
	// E
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 4.0, 6.0), vec4(0.0, 3.0, 3.1, 3.0), vec4(0.0, 0.0, 4.0, 0.0),
	// I
	vec4(2.0, 0.0, 2.0, 6.0), vec4(0.9, 6.0, 3.1, 6.0), vec4(0.9, 0.0, 3.1, 0.0),
	// K
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 2.4, 4.0, 6.0), vec4(1.4, 3.6, 4.0, 0.0),
	// L
	vec4(0.0, 6.0, 0.0, 0.0), vec4(0.0, 0.0, 4.0, 0.0),
	// M
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 2.0, 3.0), vec4(2.0, 3.0, 4.0, 6.0), vec4(4.0, 6.0, 4.0, 0.0),
	// N
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 4.0, 0.0), vec4(4.0, 0.0, 4.0, 6.0),
	// O
	vec4(1.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 4.8), vec4(4.0, 4.8, 2.8, 6.0),
	vec4(2.8, 6.0, 1.2, 6.0), vec4(1.2, 6.0, 0.0, 4.8), vec4(0.0, 4.8, 0.0, 1.2), vec4(0.0, 1.2, 1.2, 0.0),
	// P
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 3.0, 6.0), vec4(3.0, 6.0, 4.0, 5.0), vec4(4.0, 5.0, 4.0, 3.8), vec4(4.0, 3.8, 3.0, 2.8), vec4(3.0, 2.8, 0.0, 2.8),
	// R
	vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 6.0, 3.0, 6.0), vec4(3.0, 6.0, 4.0, 5.0), vec4(4.0, 5.0, 4.0, 3.8), vec4(4.0, 3.8, 3.0, 2.8), vec4(3.0, 2.8, 0.0, 2.8), vec4(1.9, 2.8, 4.0, 0.0),
	// T
	vec4(0.0, 6.0, 4.0, 6.0), vec4(2.0, 6.0, 2.0, 0.0),
	// U
	vec4(0.0, 6.0, 0.0, 1.2), vec4(0.0, 1.2, 1.2, 0.0), vec4(1.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 6.0),
	// V
	vec4(0.0, 6.0, 2.0, 0.0), vec4(2.0, 0.0, 4.0, 6.0),
	// Z
	vec4(0.0, 6.0, 4.0, 6.0), vec4(4.0, 6.0, 0.0, 0.0), vec4(0.0, 0.0, 4.0, 0.0),
	// G
	vec4(4.0, 4.8, 2.8, 6.0), vec4(2.8, 6.0, 1.2, 6.0), vec4(1.2, 6.0, 0.0, 4.8), vec4(0.0, 4.8, 0.0, 1.2), vec4(0.0, 1.2, 1.2, 0.0),
	vec4(1.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 2.8), vec4(4.0, 2.8, 2.2, 2.8),
	// 0
	vec4(1.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 4.8), vec4(4.0, 4.8, 2.8, 6.0),
	vec4(2.8, 6.0, 1.2, 6.0), vec4(1.2, 6.0, 0.0, 4.8), vec4(0.0, 4.8, 0.0, 1.2), vec4(0.0, 1.2, 1.2, 0.0),
	// 1
	vec4(0.9, 4.8, 2.3, 6.0), vec4(2.3, 6.0, 2.3, 0.0), vec4(0.9, 0.0, 3.7, 0.0),
	// 2
	vec4(0.0, 4.8, 1.2, 6.0), vec4(1.2, 6.0, 2.8, 6.0), vec4(2.8, 6.0, 4.0, 4.8), vec4(4.0, 4.8, 4.0, 3.6), vec4(4.0, 3.6, 0.0, 0.0), vec4(0.0, 0.0, 4.0, 0.0),
	// 3
	vec4(0.0, 6.0, 4.0, 6.0), vec4(4.0, 6.0, 1.8, 3.4), vec4(1.8, 3.4, 2.8, 3.4), vec4(2.8, 3.4, 4.0, 2.2),
	vec4(4.0, 2.2, 4.0, 1.2), vec4(4.0, 1.2, 2.8, 0.0), vec4(2.8, 0.0, 1.2, 0.0), vec4(1.2, 0.0, 0.0, 1.2),
	// 4
	vec4(3.0, 0.0, 3.0, 6.0), vec4(3.0, 6.0, 0.0, 1.8), vec4(0.0, 1.8, 4.0, 1.8),
	// 5
	vec4(4.0, 6.0, 0.0, 6.0), vec4(0.0, 6.0, 0.0, 3.4), vec4(0.0, 3.4, 2.8, 3.4), vec4(2.8, 3.4, 4.0, 2.2),
	vec4(4.0, 2.2, 4.0, 1.2), vec4(4.0, 1.2, 2.8, 0.0), vec4(2.8, 0.0, 0.0, 0.0),
	// 6
	vec4(3.8, 6.0, 1.2, 6.0), vec4(1.2, 6.0, 0.0, 4.8), vec4(0.0, 4.8, 0.0, 1.2), vec4(0.0, 1.2, 1.2, 0.0),
	vec4(1.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 2.4), vec4(4.0, 2.4, 2.8, 3.6), vec4(2.8, 3.6, 0.0, 3.6),
	// 7
	vec4(0.0, 6.0, 4.0, 6.0), vec4(4.0, 6.0, 1.5, 0.0),
	// 8
	vec4(0.0, 0.0, 4.0, 0.0), vec4(4.0, 0.0, 4.0, 6.0), vec4(4.0, 6.0, 0.0, 6.0), vec4(0.0, 6.0, 0.0, 0.0), vec4(0.0, 3.2, 4.0, 3.2),
	// 9
	vec4(0.2, 0.0, 2.8, 0.0), vec4(2.8, 0.0, 4.0, 1.2), vec4(4.0, 1.2, 4.0, 4.8), vec4(4.0, 4.8, 2.8, 6.0),
	vec4(2.8, 6.0, 1.2, 6.0), vec4(1.2, 6.0, 0.0, 4.8), vec4(0.0, 4.8, 0.0, 3.6), vec4(0.0, 3.6, 1.2, 2.4), vec4(1.2, 2.4, 4.0, 2.4));

const float ADVANCE = 5.3;
const float STROKE = 0.62;

float seg_dist(vec2 p, vec4 s) {
	vec2 pa = p - s.xy;
	vec2 ba = s.zw - s.xy;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance (glyph units) from p to glyph g; g < 0 is a space.
float glyph(int g, vec2 p) {
	if (g < 0) {
		return 1e3;
	}
	int start = G_START[g];
	int count = G_COUNT[g];
	float d = 1e3;
	for (int i = 0; i < 9; i++) {
		if (i >= count) {
			break;
		}
		d = min(d, seg_dist(p, SEG[start + i]));
	}
	return d;
}

// Coverage of a glyph cell: `q` is metres from the text's bottom-left corner, `h` the cap
// height, g the glyph. Past a few pixels a letter it greys out to its average ink.
float ink(int g, vec2 q, float h) {
	float unit = h / 6.0;
	vec2 p = q / unit;
	float d = glyph(g, p);
	float aa = max(fwidth(p.x), fwidth(p.y));
	float sharp = 1.0 - smoothstep(STROKE - aa, STROKE + aa, d);
	float avg = 0.32 * step(0.0, p.x) * step(p.x, 4.0) * step(0.0, p.y) * step(p.y, 6.0);
	return mix(sharp, avg, smoothstep(0.35, 1.2, aa));
}

float name_line(int lv, vec2 q, float h) {
	int n = NAME_LEN[lv];
	if (n == 0) {
		return 0.0;
	}
	float unit = h / 6.0;
	float cell = floor(q.x / (unit * ADVANCE));
	if (cell < 0.0 || cell >= float(n) || q.y < -unit || q.y > h + unit) {
		return 0.0;
	}
	return ink(TEXT[NAME_AT[lv] + int(cell)], q - vec2(cell * unit * ADVANCE, 0.0), h);
}

float name_width(int lv, float h) {
	return (float(NAME_LEN[lv]) * ADVANCE - 1.3) * h / 6.0;
}

// The livery's mark, p centred with radius 1. Returns coverage.
float mark(int m, vec2 p, float fw) {
	float d = 1e3;
	float r = length(p);
	if (m == 0) {
		// A wave cut through a disc.
		float wave = abs(p.y - 0.22 * sin(p.x * 3.4) + 0.05) - 0.13;
		d = max(r - 1.0, -wave);
	} else if (m == 1) {
		float dia = abs(abs(p.x) + abs(p.y) - 0.78) - 0.16;
		d = min(dia, r - 0.24);
	} else if (m == 2) {
		// Three chevrons pointing right.
		float cx = p.x + 0.55;
		for (int i = 0; i < 3; i++) {
			float x = cx - float(i) * 0.5;
			d = min(d, abs(x + abs(p.y) * 0.9 - 0.35) - 0.11);
		}
		d = max(d, abs(p.y) - 0.85);
		d = max(d, abs(p.x) - 1.0);
	} else if (m == 3) {
		// A sail over a hull line.
		float sail = max(max(-(p.x + 0.55), p.x + 0.55 - (0.9 - p.y) * 0.75), max(-(p.y + 0.35), p.y - 0.95));
		float hull = max(abs(p.y + 0.62) - 0.12, abs(p.x) - 0.95);
		d = min(sail, hull);
	} else if (m == 4) {
		d = min(abs(r - 0.82) - 0.14, abs(r - 0.42) - 0.12);
	} else if (m == 5) {
		// A sun: a disc and eight rays.
		float a = atan(p.y, p.x);
		float ray = max(abs(fract(a / 0.785398 + 0.5) - 0.5) * r * 0.785398 - 0.08, max(0.62 - r, r - 1.0));
		d = min(r - 0.44, ray);
	}
	return 1.0 - smoothstep(-fw, fw, d);
}
