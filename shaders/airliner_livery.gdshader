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

global uniform float lamp_factor;

// -1: take the livery from INSTANCE_CUSTOM.r (MultiMesh); 0..5 to fix it (a single jet).
uniform float livery = -1.0;
// Cabin windows lit after dark (a parked jet being cleaned, a flight on approach).
uniform float cabin_glow = 0.5;

varying vec3 mpos;
varying vec3 mnrm;
varying float v_livery;

void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
	v_livery = livery >= 0.0 ? livery : floor(INSTANCE_CUSTOM.r * 8.0 + 0.5);
}

// [fin, accent, belly, cheatline], linear.
void livery_colours(float id, out vec3 fin, out vec3 accent, out vec3 belly, out vec3 cheat, out float mark) {
	fin = vec3(0.012, 0.022, 0.08);
	accent = vec3(0.85, 0.30, 0.03);
	belly = vec3(0.32, 0.33, 0.35);
	cheat = vec3(0.012, 0.022, 0.08);
	mark = 0.0;
	if (id > 0.5 && id < 1.5) {
		// A sunset carrier: red-orange fin, yellow accent, white belly.
		fin = vec3(0.62, 0.07, 0.015);
		accent = vec3(0.95, 0.62, 0.05);
		belly = vec3(0.78, 0.78, 0.78);
		cheat = vec3(0.62, 0.07, 0.015);
		mark = 1.0;
	} else if (id > 1.5 && id < 2.5) {
		// Coastal blue.
		fin = vec3(0.06, 0.24, 0.62);
		accent = vec3(0.30, 0.62, 0.90);
		belly = vec3(0.06, 0.24, 0.62);
		cheat = vec3(0.30, 0.62, 0.90);
		mark = 2.0;
	} else if (id > 2.5 && id < 3.5) {
		// Evergreen.
		fin = vec3(0.012, 0.10, 0.035);
		accent = vec3(0.55, 0.75, 0.15);
		belly = vec3(0.30, 0.31, 0.32);
		cheat = vec3(0.012, 0.10, 0.035);
		mark = 3.0;
	} else if (id > 3.5 && id < 4.5) {
		// Plum and gold.
		fin = vec3(0.10, 0.02, 0.16);
		accent = vec3(0.80, 0.55, 0.12);
		belly = vec3(0.10, 0.02, 0.16);
		cheat = vec3(0.80, 0.55, 0.12);
		mark = 2.0;
	} else if (id > 4.5) {
		// Crimson.
		fin = vec3(0.42, 0.006, 0.012);
		accent = vec3(0.80, 0.80, 0.80);
		belly = vec3(0.30, 0.31, 0.32);
		cheat = vec3(0.42, 0.006, 0.012);
		mark = 1.0;
	}
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
	vec3 fin, accent, belly, cheat;
	float mark;
	livery_colours(v_livery, fin, accent, belly, cheat, mark);
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
		if (mark < 0.5) {
			m = 1.0 - smoothstep(0.055 - aa, 0.055 + aa, length(q));
			m -= 1.0 - smoothstep(0.035 - aa, 0.035 + aa, length(q - vec2(0.012, 0.01)));
		} else if (mark < 1.5) {
			float band = q.y + q.x * 0.9;
			m = smoothstep(-0.02 - aa, -0.02 + aa, band) * (1.0 - smoothstep(0.03 - aa, 0.03 + aa, band));
		} else if (mark < 2.5) {
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
		col = mix(col, fin, sweep * step(0.5, mark));
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
		emit = vec3(1.0, 0.78, 0.48) * win * cabin_glow * lamp_factor * 0.9;
	} else {
		// Wings, tailplane, flap fairings: light grey metal with a darker walkway.
		col = vec3(0.55, 0.57, 0.60);
		rough = 0.42;
		metal = 0.45;
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = cs_out(emit);
}
