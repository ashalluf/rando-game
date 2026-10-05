shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// The marina's boats (BoatMesh, MarinaBuild): one MultiMesh per type, level and dock, so the
// whole basin is a few dozen draws. What a vertex is rides in COLOR.a (BoatMesh.Region / 16),
// its colour in COLOR.rgb (sRGB as written; vertex colours arrive raw on both renderers).
//
// Per instance (INSTANCE_CUSTOM; the instance COLOR is white - it multiplies COLOR, region and
// all): rgb the hull's paint (sRGB), a = flags / 64: canvas index (0-5) + 8 lit cabin + 16 anchor
// light + 32 on stands (no bobbing). A boat rides the water: a heave, a roll and a pitch about its
// waterline, each phased by the boat's TRUE world position (origin_shift: an origin re-centre must
// not jolt the basin), small boats livelier than big ones, more in a wind. A solo boat (a plain
// MeshInstance3D: MarinaTraffic's) reads `solo_*` instead and is moved by its node; it does not bob.
//
// Linear on both renderers (color_space.gdshaderinc): COLOR and INSTANCE_CUSTOM are sRGB in, the
// albedo goes out through cs_out().

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float wind_factor;
global uniform float road_wetness;
global uniform vec3 origin_shift;

#include "res://shaders/color_space.gdshaderinc"

uniform float solo = 0.0;
uniform vec3 solo_paint = vec3(0.93, 0.93, 0.91);
uniform float solo_flags = 0.0;
// Bobbing: heave (m), roll and pitch (radians) for a 10 m boat in calm water.
uniform float heave = 0.035;
uniform float roll = 0.022;
uniform float pitch = 0.007;
// The canvas colours (Marina.CANVAS, sRGB; checked by tests/marina_checks.gd).
const vec3 CANVAS[6] = vec3[6](vec3(0.1, 0.14, 0.3), vec3(0.12, 0.3, 0.55), vec3(0.35, 0.09, 0.12), vec3(0.1, 0.25, 0.17), vec3(0.62, 0.55, 0.42), vec3(0.4, 0.42, 0.44));
// Bottom paint: red or navy antifouling.
const vec3 BOTTOM_RED = vec3(0.42, 0.08, 0.06);
const vec3 BOTTOM_NAVY = vec3(0.07, 0.09, 0.16);
// Cabin light after dark, and the anchor light's strength (HDR: the glow pass blooms it).
uniform vec3 cabin_light = vec3(1.0, 0.72, 0.42);
uniform float cabin_energy = 2.2;
uniform float anchor_energy = 14.0;

varying vec3 v_local;
varying flat float v_region;
varying vec3 v_paint;
varying flat float v_flags;
varying float v_seed;

float bt_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bt_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bt_hash(i), bt_hash(i + vec2(1.0, 0.0)), f.x), mix(bt_hash(i + vec2(0.0, 1.0)), bt_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_region = floor(COLOR.a * 16.0);
	float flags = solo > 0.5 ? solo_flags : floor(INSTANCE_CUSTOM.a * 64.0 + 0.5);
	v_flags = flags;
	v_paint = solo > 0.5 ? solo_paint : INSTANCE_CUSTOM.rgb;
	vec3 o = MODEL_MATRIX[3].xyz + origin_shift;
	float ph = bt_hash(floor(o.xz * 3.0)) * 6.2831;
	v_seed = fract(ph * 7.31);
	bool stands = mod(floor(flags / 32.0), 2.0) > 0.5;
	if (solo < 0.5 && !stands) {
		float scale = length(MODEL_MATRIX[2].xyz);
		// Length of this boat (the meshes are built to a reference size and scaled): a small
		// boat bobs more and faster.
		float lively = clamp(1.0 / max(scale, 0.3), 0.6, 1.8);
		float w = 0.7 + 0.5 * clamp(wind_factor, 0.0, 2.0);
		float t = TIME;
		float hv = (sin(t * 1.55 + ph) * 0.7 + sin(t * 0.83 + ph * 1.7) * 0.5) * heave * w;
		float rl = (sin(t * 1.21 + ph * 2.3) + 0.4 * sin(t * 2.07 + ph)) * roll * w * lively;
		float pt = sin(t * 1.05 + ph * 0.6) * pitch * w * lively;
		// Rotate about the waterline origin: roll about the boat's length (z), pitch about x.
		float cr = cos(rl);
		float sr = sin(rl);
		float cp = cos(pt);
		float sp = sin(pt);
		mat3 r_roll = mat3(vec3(cr, sr, 0.0), vec3(-sr, cr, 0.0), vec3(0.0, 0.0, 1.0));
		mat3 r_pitch = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cp, -sp), vec3(0.0, sp, cp));
		mat3 r = r_pitch * r_roll;
		// The heave is in metres of the world, not of the scaled mesh.
		VERTEX = r * VERTEX + vec3(0.0, hv / max(scale, 0.3), 0.0);
		NORMAL = r * NORMAL;
	}
}

void fragment() {
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float region = v_region;
	float flags = v_flags;
	float canvas_i = mod(flags, 8.0);
	bool lit = mod(floor(flags / 8.0), 2.0) > 0.5;
	bool anchor = mod(floor(flags / 16.0), 2.0) > 0.5;
	bool stands = mod(floor(flags / 32.0), 2.0) > 0.5;
	vec3 paint = cs_srgb_to_linear(v_paint);
	vec3 alb = base;
	float rough = 0.4;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	// Godot has already turned NORMAL toward the camera on a back face (cull_disabled; both
	// renderers, probed 2026-10-05): flipping it again lit every inside face - an open cockpit, the
	// underside of a canvas cover - as if it faced away from the light.
	vec3 nrm = NORMAL;
	if (region < 0.5) {
		// The hull: gelcoat in the boat's paint above the waterline, a boot stripe on some, the
		// waterline's scum, antifouling under it (the yard shows it).
		alb = paint;
		rough = 0.12;
		float y = v_local.y;
		float boot = step(0.55, v_seed);
		vec3 stripe = mix(cs_srgb_to_linear(CANVAS[int(canvas_i)]), vec3(0.02), step(0.8, v_seed));
		alb = mix(alb, stripe, boot * step(0.06, y) * step(y, 0.16));
		vec3 bottom = mix(BOTTOM_RED, BOTTOM_NAVY, step(0.5, fract(v_seed * 3.7)));
		alb = mix(alb, bottom, step(y, 0.05));
		if (!stands) {
			// A greenish scum line at the water and streaks down from the scuppers on some.
			float scum = smoothstep(0.24, 0.05, y) * step(0.0, y) * 0.55;
			alb = mix(alb, vec3(0.06, 0.07, 0.04), scum);
		}
		float streak = bt_noise(vec2(v_local.z * 2.3, y * 0.25)) * smoothstep(0.2, 1.1, y);
		alb *= 1.0 - 0.12 * smoothstep(0.62, 0.95, streak) * step(0.5, fract(v_seed * 11.0));
		if (y < 0.05) {
			rough = 0.75;
		}
	} else if (region < 1.5) {
		alb = mix(BOTTOM_RED, BOTTOM_NAVY, step(0.5, fract(v_seed * 3.7)));
		rough = 0.8;
	} else if (region < 2.5) {
		// Moulded non-skid: a fine diamond texture, grey with use.
		float d = bt_noise(UV * 38.0) * 0.5 + bt_noise(UV * 9.0) * 0.5;
		alb = base * (0.92 + 0.08 * d);
		rough = 0.65;
	} else if (region < 3.5) {
		alb = base;
		rough = 0.18;
	} else if (region < 4.5) {
		// Tinted glass; a lit cabin's windows glow after dark, pane by pane.
		alb = base;
		rough = 0.04;
		spec = 0.7;
		if (lit) {
			float cell = bt_hash(floor(v_local.xz * vec2(1.4, 0.9)) + v_seed * 13.0);
			float on = smoothstep(0.15, 0.6, lamp_factor) * step(0.2, cell);
			emit = cs_srgb_to_linear(cabin_light) * cabin_energy * on * (0.55 + 0.45 * cell);
		}
	} else if (region < 5.5) {
		alb = base;
		metal = 0.9;
		rough = 0.28;
	} else if (region < 6.5) {
		// Canvas: the boat's colour, woven.
		alb = cs_srgb_to_linear(CANVAS[int(canvas_i)]) * (0.9 + 0.1 * bt_noise(UV * 60.0));
		rough = 0.88;
		spec = 0.3;
	} else if (region < 7.5) {
		// Teak: planks along the boat, grey where the sun has had it.
		float plank = fract(v_local.x * 9.0);
		float seam = smoothstep(0.0, 0.06, plank) * smoothstep(1.0, 0.94, plank);
		float grain = bt_noise(vec2(v_local.x * 40.0, v_local.z * 2.0));
		alb = mix(base * 0.55, base, seam) * (0.85 + 0.25 * grain);
		alb = mix(alb, vec3(0.32, 0.31, 0.29), 0.35 * step(0.5, v_seed));
		rough = 0.7;
	} else if (region < 8.5) {
		// The anchor light (and the radar arch's): on after dark when the boat shows one.
		alb = vec3(0.6);
		rough = 0.2;
		float on = anchor ? smoothstep(0.2, 0.6, lamp_factor) : 0.0;
		emit = vec3(1.0, 0.95, 0.85) * anchor_energy * on;
	} else if (region < 9.5) {
		alb = base;
		rough = 0.6;
	} else if (region < 10.5) {
		// Sailcloth, a little weathered.
		alb = base * (0.94 + 0.06 * bt_noise(UV * 25.0));
		rough = 0.8;
	} else {
		// The outboard's cowl: glossy black.
		alb = base;
		rough = 0.18;
		spec = 0.6;
	}
	// Rain wets the decks and the canvas.
	rough = mix(rough, rough * 0.4, clamp(road_wetness, 0.0, 1.0) * step(region, 7.5) * (1.0 - step(5.5, region) * step(region, 6.5) * 0.6));
	NORMAL = nrm;
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = cs_out(emit);
}
