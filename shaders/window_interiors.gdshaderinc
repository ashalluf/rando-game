// The rooms behind a building's windows, second pass (WindowInteriors, docs/HANDOFF.md "Rooms
// behind the windows, second pass"): which buildings are HOMES rather than offices, what hangs
// at each home window (drapes, sheers, a roller blind, a venetian, vertical blinds, nothing),
// which rooms watch TV, which windows stand open by day with the curtain moving, who walks past
// a lit room, which offices have somebody at the desk. All of it rolled from INTEGERS on the
// building's seed and the window's (face, row, col) - wl_hash() of window_lights.gdshaderinc -
// so the near walls (building.gdshader, which also traces the rooms: window_rooms.gdshaderinc)
// and the far boxes (building_lod.gdshader) agree to the bit, and scripts/world/window_interiors.gd
// is the GDScript copy (tests/window_interiors_checks.gd reads these numbers back).
// Salts 100-112 belong to this pass. Include AFTER window_lights.gdshaderinc.
// Shader includes use // comments.

#ifndef WINDOW_INTERIORS_DECLARED
#define WINDOW_INTERIORS_DECLARED
// 1 on, 0 the A/B (WINDOW_INTERIORS=0: every window is the first pass's office room).
global uniform float window_interiors;
#endif

// The share of buildings that are homes, per window style (Building.WindowStyle: punched,
// ribbon, curtain wall, narrow), in per mille of the salt-100 roll. WindowInteriors.HOME_SHARE.
const int WI_HOME_PUNCHED = 520;
const int WI_HOME_RIBBON = 90;
const int WI_HOME_CURTAIN = 160;
const int WI_HOME_NARROW = 380;
// Per mille of a home's windows: what hangs there (cumulative, salt 101): drapes, sheers, a
// roller blind, a venetian, vertical blinds, the rest bare. WindowInteriors.COVER_EDGES.
const int WI_COVER_DRAPES = 300;
const int WI_COVER_SHEER = 520;
const int WI_COVER_ROLLER = 700;
const int WI_COVER_VENETIAN = 830;
const int WI_COVER_VERTICAL = 900;
// Per mille of lit home rooms with the TV on (salt 102), of home windows open by day (103), of
// lit home rooms somebody walks through now and then (104), of office rooms with somebody at the
// desk by day (106).
const int WI_TV = 300;
const int WI_OPEN = 70;
const int WI_WALKER = 450;
const int WI_WORKER = 560;

uint wi_key(float b_seed, float face, float row, float col) {
	return wl_face_row(b_seed, face, row) + uint(clamp(col, 0.0, 255.0));
}

int wi_pm(uint key, uint salt) {
	return int(wl_hash(key, salt) % 1000u);
}

// Is this building flats rather than offices? Off with the pass.
bool wi_home(float b_seed, int style) {
	if (window_interiors < 0.5) {
		return false;
	}
	uint sd = uint(clamp(b_seed, 0.0, 999.0) + 0.5);
	int share = style == 0 ? WI_HOME_PUNCHED : (style == 1 ? WI_HOME_RIBBON : (style == 2 ? WI_HOME_CURTAIN : WI_HOME_NARROW));
	return wi_pm(sd, 100u) < share;
}

// 0 drapes, 1 sheers, 2 roller blind, 3 venetian, 4 vertical blinds, 5 bare.
int wi_cover(uint key) {
	int r = wi_pm(key, 101u);
	if (r < WI_COVER_DRAPES) return 0;
	if (r < WI_COVER_SHEER) return 1;
	if (r < WI_COVER_ROLLER) return 2;
	if (r < WI_COVER_VENETIAN) return 3;
	if (r < WI_COVER_VERTICAL) return 4;
	return 5;
}

// How far it is drawn: drapes 0 open .. 1 shut, a blind 0 up .. 1 down. 0.05..0.95, salt 107.
float wi_draw(uint key) {
	return 0.05 + 0.9 * float(wi_pm(key, 107u)) / 1000.0;
}

// The fabric's colour (salt 108), LINEAR: cream, white, oatmeal, grey, a dusty blue, terracotta,
// sage, charcoal. WindowInteriors.FABRICS.
vec3 wi_fabric(uint key) {
	int i = int(wl_hash(key, 108u) % 8u);
	if (i == 0) return vec3(0.78, 0.70, 0.55);
	if (i == 1) return vec3(0.86, 0.85, 0.82);
	if (i == 2) return vec3(0.58, 0.52, 0.42);
	if (i == 3) return vec3(0.42, 0.43, 0.44);
	if (i == 4) return vec3(0.30, 0.38, 0.50);
	if (i == 5) return vec3(0.55, 0.30, 0.20);
	if (i == 6) return vec3(0.40, 0.46, 0.34);
	return vec3(0.16, 0.16, 0.17);
}

bool wi_tv(uint key) {
	return wi_pm(key, 102u) < WI_TV;
}

// Open by day: the lower sash up, the curtain moving in the draught. Only drapes and sheers.
bool wi_open(uint key) {
	int c = wi_cover(key);
	return (c == 0 || c == 1) && wi_pm(key, 103u) < WI_OPEN;
}

bool wi_walker(uint key) {
	return wi_pm(key, 104u) < WI_WALKER;
}

bool wi_worker(uint key) {
	return wi_pm(key, 106u) < WI_WORKER;
}

// A home's lamps, as a multiplier on the building's lit colour with its luminance kept (salt
// 105): warm incandescent, soft white, a paper shade's amber, a cool LED. WindowInteriors.TONES.
vec3 wi_home_tone(uint key) {
	int i = int(wl_hash(key, 105u) % 4u);
	vec3 m = vec3(1.18, 0.92, 0.62);
	if (i == 1) m = vec3(1.05, 0.98, 0.86);
	if (i == 2) m = vec3(1.25, 0.86, 0.50);
	if (i == 3) m = vec3(0.90, 0.98, 1.20);
	return m / dot(m, vec3(0.2126, 0.7152, 0.0722));
}

// A TV's light (a multiplier like wi_home_tone): blue-white, cutting between shots every second
// or so, flickering within one. `t` is TIME. Its average over time is WI_TV_MEAN, which the far
// boxes use once a window is a few pixels.
const vec3 WI_TV_MEAN = vec3(0.62, 0.86, 1.45);
vec3 wi_tv_light(uint key, float t) {
	float shot = floor(t * 0.9 + float(key % 997u) * 0.137);
	float k = float(wl_hash(key + uint(shot), 109u) % 1000u) / 1000.0;
	float flick = 0.85 + 0.15 * sin(t * 23.0 + float(key % 97u)) * sin(t * 7.3);
	vec3 c = mix(vec3(0.50, 0.78, 1.55), vec3(0.78, 0.92, 1.30), k);
	return c * (0.55 + 0.9 * k) * flick;
}

// The mean colour of what hangs at a home window by day, and how much of the pane it covers,
// for the far box (the near trace draws the real thing): w = coverage 0..1.
vec4 wi_cover_mean(uint key) {
	int c = wi_cover(key);
	float d = wi_draw(key);
	vec3 f = wi_fabric(key);
	if (c == 0) return vec4(f, 0.18 + 0.7 * d * 0.6);
	if (c == 1) return vec4(mix(f, vec3(0.9), 0.5), 0.45);
	if (c == 2) return vec4(f, d * 0.85);
	if (c == 3) return vec4(vec3(0.82, 0.80, 0.75), d * 0.8);
	if (c == 4) return vec4(vec3(0.80, 0.79, 0.76), 0.55);
	return vec4(f, 0.0);
}
