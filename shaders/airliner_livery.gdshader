shader_type spatial;
render_mode cull_back;

// Liveries for the airliner model (assets/models/jet_airliner.glb), painted from the model's own
// space instead of its texture (a Meshy atlas that reads as camouflage). The model lies along x,
// nose at -0.951, tail at +0.951 (1.902 units long), symmetric in z, wheels at y -0.342; Airport
// and AmbientJet scale it to 38 m. Regions, in model units:
//   fuselage  |z| < 0.12, y -0.245 .. 0.01, before the tail cone: white over a belly colour, a
//             cheatline, a row of cabin windows each side, the cockpit glazing, door outlines;
//   fin       y > 0, aft: the airline's colour and its mark (a disc, a band, a diamond, a chevron);
//   engines   the nacelles under the wings, in the accent colour with a bright intake lip;
//   wings and tailplane: light grey metal; the gear: dark.
// Six invented airlines (never a real carrier's scheme): `livery` picks one, or on a MultiMesh
// INSTANCE_CUSTOM.r * 8 does (Airport's parked jets). Colours are LINEAR (color_space).
// Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"
// The stroke font (glyph(), ink()) the containers' lettering uses, for the titles.
#include "res://shaders/port_lettering.gdshaderinc"

global uniform float lamp_factor;

// -1: take the livery from INSTANCE_CUSTOM.r (MultiMesh); 0..5 to fix it (a single jet).
uniform float livery = -1.0;
// Cabin windows lit after dark (a parked jet being cleaned, a flight on approach).
uniform float cabin_glow = 0.5;
// The close-up pass (AirportApron, refcam2 "airport_apron"): the airline's name along the crown,
// a registration aft, panel seams with a tone per panel, bare-metal leading edges, dark fan faces
// and exhausts, belly and tail-cone grime. 0 is the old flat livery (AIRPORT_APRON=0).
uniform float detail = 1.0;

varying vec3 mpos;
varying vec3 mnrm;
varying float v_livery;

void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
	v_livery = livery >= 0.0 ? livery : floor(INSTANCE_CUSTOM.r * 8.0 + 0.5);
}

// [fin, accent, belly, cheatline], linear.
void livery_colours(float id, out vec3 fin, out vec3 accent, out vec3 belly, out vec3 cheat, out float mark_id) {
	fin = vec3(0.012, 0.022, 0.08);
	accent = vec3(0.85, 0.30, 0.03);
	belly = vec3(0.32, 0.33, 0.35);
	cheat = vec3(0.012, 0.022, 0.08);
	mark_id = 0.0;
	if (id > 0.5 && id < 1.5) {
		// A sunset carrier: red-orange fin, yellow accent, white belly.
		fin = vec3(0.62, 0.07, 0.015);
		accent = vec3(0.95, 0.62, 0.05);
		belly = vec3(0.78, 0.78, 0.78);
		cheat = vec3(0.62, 0.07, 0.015);
		mark_id = 1.0;
	} else if (id > 1.5 && id < 2.5) {
		// Coastal blue.
		fin = vec3(0.06, 0.24, 0.62);
		accent = vec3(0.30, 0.62, 0.90);
		belly = vec3(0.06, 0.24, 0.62);
		cheat = vec3(0.30, 0.62, 0.90);
		mark_id = 2.0;
	} else if (id > 2.5 && id < 3.5) {
		// Evergreen.
		fin = vec3(0.012, 0.10, 0.035);
		accent = vec3(0.55, 0.75, 0.15);
		belly = vec3(0.30, 0.31, 0.32);
		cheat = vec3(0.012, 0.10, 0.035);
		mark_id = 3.0;
	} else if (id > 3.5 && id < 4.5) {
		// Plum and gold.
		fin = vec3(0.10, 0.02, 0.16);
		accent = vec3(0.80, 0.55, 0.12);
		belly = vec3(0.10, 0.02, 0.16);
		cheat = vec3(0.80, 0.55, 0.12);
		mark_id = 2.0;
	} else if (id > 4.5) {
		// Crimson.
		fin = vec3(0.42, 0.006, 0.012);
		accent = vec3(0.80, 0.80, 0.80);
		belly = vec3(0.30, 0.31, 0.32);
		cheat = vec3(0.42, 0.006, 0.012);
		mark_id = 1.0;
	}
}

// The airlines' names (invented: none is a real carrier), glyph indices of port_lettering's font
// (0 A, 1 D, 2 E, 3 I, 4 K, 5 L, 6 M, 7 N, 8 O, 9 P, 10 R, 11 T, 12 U, 13 V, 14 Z, 15 G, 16.. the
// digits): VANTERRA, PALMERA, MARINDO, VERDANT, AMETRIA, KARMINE; then the registrations, five
// glyphs each: N317V N482P N905M N226G N571K N648R.
const int AL_AT[6] = int[](0, 8, 15, 22, 29, 36);
const int AL_LEN[6] = int[](8, 7, 7, 7, 7, 7);
const int AL_TEXT[43] = int[](
	13, 0, 7, 11, 2, 10, 10, 0,
	9, 0, 5, 6, 2, 10, 0,
	6, 0, 10, 3, 7, 1, 8,
	13, 2, 10, 1, 0, 7, 11,
	0, 6, 2, 11, 10, 3, 0,
	4, 0, 10, 6, 3, 7, 2);
const int AL_REG[30] = int[](
	7, 19, 17, 23, 13,
	7, 20, 24, 18, 9,
	7, 25, 16, 21, 6,
	7, 18, 18, 22, 15,
	7, 21, 23, 17, 4,
	7, 22, 20, 24, 10);

// Coverage of a line of `n` glyphs from `table` at `at`, `q` from its bottom-left (model units),
// cap height `h`.
// `px` is the pixel's size in model units, taken outside every branch (derivatives in a branch
// read 0 on llvmpipe); a letter under a pixel or so greys out to its average ink.
float al_line(int id, vec2 q, float h, bool reg, float px) {
	float unit = h / 6.0;
	float cell = floor(q.x / (unit * ADVANCE));
	int n = reg ? 5 : AL_LEN[id];
	if (cell < 0.0 || cell >= float(n) || q.y < -unit || q.y > h + unit) {
		return 0.0;
	}
	int g = reg ? AL_REG[id * 5 + int(cell)] : AL_TEXT[AL_AT[id] + int(cell)];
	vec2 gp = (q - vec2(cell * unit * ADVANCE, 0.0)) / unit;
	float d = glyph(g, gp);
	float a = px / unit;
	float sharp = 1.0 - smoothstep(STROKE - a, STROKE + a, d);
	float avg = 0.32 * step(0.0, gp.x) * step(gp.x, 4.0) * step(0.0, gp.y) * step(gp.y, 6.0);
	return mix(sharp, avg, smoothstep(0.35, 1.2, a));
}

float al_width(int id, float h, bool reg) {
	return (float(reg ? 5 : AL_LEN[id]) * ADVANCE - 1.3) * h / 6.0;
}

float al_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// A seam `width` wide every `period` along x, box-filtered by the pixel: under a pixel it is its
// average, so it greys out instead of shimmering.
float al_seam(float x, float period, float width, float fw_in) {
	float d = abs(fract(x / period + 0.5) - 0.5) * period;
	float fw = max(fw_in, 1e-5);
	float c = 1.0 - smoothstep(width * 0.5, width * 0.5 + fw, d);
	return c * min(1.0, width / fw) + (1.0 - min(1.0, width / fw)) * (width / period);
}

float box2(vec2 p, vec2 lo, vec2 hi, float aa) {
	vec2 a = smoothstep(lo - aa, lo + aa, p) * (1.0 - smoothstep(hi - aa, hi + aa, p));
	return a.x * a.y;
}

void fragment() {
	vec3 p = mpos;
	float u = (p.x + 0.951) / 1.902;
	float az = abs(p.z);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.75 + 1e-5;
	// The pixel in metres along and up the jet, and across it, for the close-up pass.
	float fw_m = (max(fwidth(p.x), fwidth(p.y)) + 1e-6) * 20.0;
	float fw_z = fwidth(abs(p.z)) * 20.0 + 1e-6;
	float glaze = 0.0;
	vec3 fin, accent, belly, cheat;
	float mark_id;
	livery_colours(v_livery, fin, accent, belly, cheat, mark_id);
	vec3 white = vec3(0.80, 0.81, 0.82);
	vec3 grey = vec3(0.42, 0.44, 0.47);
	vec3 col = white;
	float rough = 0.32;
	float metal = 0.0;
	vec3 emit = vec3(0.0);

	bool fuselage = az < 0.125 && p.y > -0.25 && p.y < 0.012 && u < 0.92;
	bool tail_fin = p.y > -0.005 && u > 0.70 && az < 0.06;
	bool engine = u > 0.30 && u < 0.52 && az > 0.18 && az < 0.39 && p.y < -0.115 && p.y > -0.27;
	bool gear = p.y < -0.25;
	if (tail_fin) {
		col = fin;
		// The mark, in the fin's own (u, y) frame.
		vec2 q = vec2((u - 0.86) * 1.902, p.y - 0.17);
		float m = 0.0;
		if (mark_id < 0.5) {
			m = 1.0 - smoothstep(0.055 - aa, 0.055 + aa, length(q));
			m -= 1.0 - smoothstep(0.035 - aa, 0.035 + aa, length(q - vec2(0.012, 0.01)));
		} else if (mark_id < 1.5) {
			float band = q.y + q.x * 0.9;
			m = smoothstep(-0.02 - aa, -0.02 + aa, band) * (1.0 - smoothstep(0.03 - aa, 0.03 + aa, band));
		} else if (mark_id < 2.5) {
			m = 1.0 - smoothstep(0.06 - aa, 0.06 + aa, abs(q.x) + abs(q.y));
		} else {
			float c = abs(q.x * 1.2) + q.y;
			m = smoothstep(-0.01 - aa, -0.01 + aa, c) * (1.0 - smoothstep(0.035 - aa, 0.035 + aa, c)) * step(abs(q.x), 0.08);
		}
		col = mix(col, accent, clamp(m, 0.0, 1.0));
	} else if (engine) {
		col = accent;
		// The bright intake lip at the front of the nacelle.
		col = mix(col, vec3(0.62, 0.63, 0.65), smoothstep(0.322, 0.315, u));
		rough = 0.3;
		metal = 0.2;
	} else if (gear) {
		col = vec3(0.05);
		rough = 0.6;
	} else if (fuselage) {
		col = white;
		// Belly below the waterline, and the cheatline above it.
		col = mix(col, belly, smoothstep(-0.168 + aa, -0.168 - aa, p.y));
		float cl = box2(vec2(u, p.y), vec2(0.06, -0.138), vec2(0.88, -0.128), aa);
		col = mix(col, cheat, cl);
		// The rear sweep in the fin colour.
		float sweep = smoothstep(0.70, 0.74, u) * smoothstep(-0.06 + (u - 0.70) * -0.5, -0.03 + (u - 0.70) * -0.5, p.y);
		col = mix(col, fin, sweep * step(0.5, mark_id));
		// Cabin windows: a row of rounded rectangles each side, 0.5 m apart.
		float side = smoothstep(0.06, 0.08, az);
		float pitch = 0.0254;
		float wu = (u * 1.902) / pitch;
		vec2 wq = vec2((fract(wu) - 0.5) * pitch, p.y + 0.085);
		float win = box2(wq, vec2(-0.0055, -0.0085), vec2(0.0055, 0.0085), aa);
		win *= step(0.12, u) * step(u, 0.83) * side;
		// Leave gaps at the doors.
		win *= step(0.02, abs(u - 0.095)) * step(0.02, abs(u - 0.47)) * step(0.02, abs(u - 0.80));
		// Door outlines.
		float door = 0.0;
		for (int k = 0; k < 3; k++) {
			float du = k == 0 ? 0.095 : (k == 1 ? 0.47 : 0.80);
			float d = max(abs((u - du) * 1.902) - 0.018, abs(p.y + 0.105) - 0.04);
			door = max(door, (1.0 - smoothstep(0.0, aa * 2.0, abs(d))) * side);
		}
		col = mix(col, col * 0.45, door);
		// Cockpit glazing.
		float cock = box2(vec2(u, p.y), vec2(0.028, -0.082), vec2(0.064, -0.058), aa);
		cock *= smoothstep(0.02, 0.04, az + (0.064 - u) * 0.6);
		vec3 glass = vec3(0.012, 0.014, 0.018);
		col = mix(col, glass, max(win, cock));
		rough = mix(rough, 0.06, max(win, cock));
		glaze = max(win, cock);
		emit = vec3(1.0, 0.78, 0.48) * win * cabin_glow * lamp_factor * 0.9;
	} else {
		// Wings, tailplane, flap fairings: light grey metal with a darker walkway.
		col = vec3(0.55, 0.57, 0.60);
		rough = 0.42;
		metal = 0.45;
	}
	if (detail > 0.5) {
		// Metres along the jet (38 m long) and up it.
		float sx = u * 38.0;
		float sy = p.y * 20.0;
		int id = int(clamp(v_livery, 0.0, 5.0));
		if (fuselage) {
			float side = smoothstep(0.045, 0.065, az);
			// The airline's name along the crown above the windows, reading nose to tail on the
			// left side and the same on the right (the box mirrored), and the registration aft.
			float h = 0.05;
			float x0 = 0.15 * 1.902 - 0.951;
			float w = al_width(id, h, false);
			float qx = p.z > 0.0 ? p.x - x0 : x0 + w - p.x;
			float title = al_line(id, vec2(qx, p.y + 0.066), h, false, fw_m / 20.0) * side;
			float hr = 0.022;
			float xr = 0.845 * 1.902 - 0.951;
			float wr = al_width(id, hr, true);
			float qr = p.z > 0.0 ? p.x - xr : xr + wr - p.x;
			float reg = al_line(id, vec2(qr, p.y + 0.118), hr, true, fw_m / 20.0) * side;
			// Panels: a tone of their own, seams round the frames and along the lap joints.
			vec2 cell = vec2(floor(sx / 2.15), floor((p.y + 0.3) * 20.0 / 1.6) + sign(p.z) * 7.0);
			col *= 0.965 + 0.06 * al_hash(cell + v_livery * 13.0);
			float seams = max(al_seam(sx, 2.15, 0.018, fw_m) * 0.7, max(al_seam(sy + 6.0, 1.6, 0.016, fw_m) * 0.55, 0.0));
			col *= 1.0 - 0.22 * seams * (1.0 - glaze);
			// Dirt: the belly behind the wing (the gear and the drains), streaks down off the
			// door sills, soot on the tail cone round the APU's exhaust.
			float belly_dirt = smoothstep(-0.19, -0.235, p.y) * smoothstep(0.42, 0.62, u);
			float streak = smoothstep(0.55, 0.9, al_hash(vec2(floor(sx * 3.0), 3.0))) * smoothstep(-0.10, -0.2, p.y) * smoothstep(0.35, 0.6, u);
			col *= 1.0 - 0.22 * belly_dirt - 0.07 * streak;
			col *= 1.0 - 0.45 * smoothstep(0.86, 0.92, u) * smoothstep(-0.05, -0.2, p.y);
			col = mix(col, fin, title);
			col = mix(col, vec3(0.03, 0.032, 0.036), reg * 0.9);
		} else if (engine) {
			// The fan face (looking forward out of the intake) is dark blades round a spinner,
			// the lip polished; the exhaust at the back dark heat-stained metal.
			float fwd = -mnrm.x;
			col = mix(col, vec3(0.62, 0.63, 0.65), smoothstep(0.25, 0.55, fwd) * (1.0 - smoothstep(0.7, 0.85, fwd)));
			col = mix(col, vec3(0.022, 0.023, 0.026), smoothstep(0.72, 0.86, fwd));
			col = mix(col, vec3(0.07, 0.065, 0.06), smoothstep(0.55, 0.8, mnrm.x));
			metal = mix(metal, 0.85, smoothstep(0.25, 0.55, abs(mnrm.x)));
			// Cowl seams, and grime under the nacelle.
			col *= 1.0 - 0.25 * al_seam(sx, 3.2, 0.02, fw_m);
			col *= 1.0 - 0.18 * smoothstep(-0.2, -0.26, p.y);
		} else if (!gear && !tail_fin) {
			// Wings and tailplane: bare metal leading edges, panel seams spanwise, the de-icing
			// boot / walkway darker near the root, exhaust soot behind the engines.
			float le = smoothstep(0.35, 0.75, -mnrm.x);
			col = mix(col, vec3(0.74, 0.75, 0.77), le);
			metal = mix(metal, 0.9, le);
			rough = mix(rough, 0.22, le);
			col *= 1.0 - 0.18 * max(al_seam(az * 20.0, 1.9, 0.02, fw_z), al_seam(sx, 1.4, 0.016, fw_m) * 0.6);
			col *= 0.94 + 0.08 * al_hash(vec2(floor(az * 20.0 / 1.9), floor(sx / 1.4)));
			float soot = smoothstep(0.5, 0.56, u) * (1.0 - smoothstep(0.62, 0.72, u)) * (1.0 - smoothstep(0.0, 0.08, abs(az - 0.285))) * step(mnrm.y, 0.0);
			col *= 1.0 - 0.3 * soot;
		} else if (tail_fin) {
			float le = smoothstep(0.35, 0.75, -mnrm.x);
			col = mix(col, vec3(0.70, 0.71, 0.73), le * 0.8);
			metal = mix(metal, 0.85, le);
		}
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = cs_out(emit);
}
