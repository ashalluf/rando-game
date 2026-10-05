shader_type spatial;
render_mode cull_back;
// A police station's glazing (PoliceStation): tinted glass that mirrors the sky by Fresnel by day
// and, after dark, shows the rooms behind it - TRACED, so they have parallax: each office (two
// bays wide, a storey high, OFFICE_DEPTH deep) with a ceiling of lit panels, walls lit from above,
// a dark carpet, a desk line and a blind part drawn, lit window by window in a warm or cool tube
// colour; the public lobby one double-height hall lit all night - stone floor, a ceiling of
// downlights, a back wall with a lit panel and the reception counter. UV is metres (x along the
// wall, y up from the station's base), which is what PoliceStation.Geo writes. Works in linear on
// both renderers (color_space.gdshaderinc).
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform vec4 sky_tint;

// One window bay (m along) by one storey (m up), and where the storeys start (m up).
uniform vec2 cell = vec2(1.6, 3.8);
uniform float storey_origin = 0.8;
// Share of the offices still lit at night.
uniform float lit_share = 0.62;
// 1: the public lobby (lit all night, brighter, warm; a little light by day too).
uniform float lobby = 0.0;
uniform float seed = 0.0;
// Glass body colour (linear) and how much of the sky it mirrors.
uniform vec3 tint = vec3(0.020, 0.032, 0.040);
uniform float mirror = 0.32;
uniform float night_energy = 1.6;
// The traced rooms: an office's depth, the lobby's floor, ceiling and depth (m).
uniform float office_depth = 5.5;
uniform vec3 lobby_room = vec3(0.15, 6.0, 7.5);
// 0 turns the trace off (the old flat rooms), for A/B.
uniform float trace = 1.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

// The point a ray from `p` (room frame: x along, y up, z into the room) along `rd` meets the
// room's inside, and which surface: 0 back wall, 1 ceiling, 2 floor, 3 side wall.
vec4 room_hit(vec3 p, vec3 rd, vec3 size, bool sides) {
	vec3 inv = 1.0 / max(abs(rd), vec3(1e-4));
	float tx = sides ? (rd.x > 0.0 ? (size.x - p.x) : p.x) * inv.x : 1e9;
	float ty = (rd.y > 0.0 ? (size.y - p.y) : p.y) * inv.y;
	float tz = (size.z - p.z) * inv.z;
	float t = min(tx, min(ty, tz));
	float s = t == tz ? 0.0 : (t == ty ? (rd.y > 0.0 ? 1.0 : 2.0) : 3.0);
	return vec4(p + rd * t, s);
}

void fragment() {
	vec2 uv = UV;
	vec2 q = (uv - vec2(0.0, storey_origin)) / cell;
	vec2 id = floor(vec2(q.x * 0.5, q.y));
	vec2 f = fract(q);
	float r = h21(id);
	// Mullions at the bay lines.
	float px = fwidth(q.x) + 1e-4;
	float mull = 1.0 - smoothstep(0.015, 0.015 + px * 1.5, min(f.x, 1.0 - f.x));
	vec3 sky = pow(max(sky_tint.rgb, vec3(0.0)), vec3(2.2));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 albedo = mix(tint, vec3(0.055, 0.058, 0.062), mull);
	float lit = lobby > 0.5 ? 1.0 : step(r, lit_share);
	vec3 tube = mix(vec3(1.0, 0.83, 0.62), vec3(0.82, 0.90, 1.0), step(0.55, fract(r * 7.13)));
	if (lobby > 0.5) {
		tube = vec3(1.0, 0.86, 0.68);
	}
	// The view ray in the wall's frame: x along UV.x, y up, z into the room.
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wt = normalize(cross(vec3(0.0, 1.0, 0.0), wn) + vec3(1e-5, 0.0, 0.0));
	// Which way along the wall UV.x runs, from the screen derivatives.
	float sgn = dot(dFdx(wpos), wt) * dFdx(uv.x) + dot(dFdy(wpos), wt) * dFdy(uv.x);
	wt *= sgn < 0.0 ? -1.0 : 1.0;
	vec3 d = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 rd = vec3(dot(d, wt), d.y, max(dot(d, -wn), 0.02));
	vec3 room;
	if (trace < 0.5 || abs(wn.y) > 0.5) {
		float ceiling = smoothstep(0.62, 0.96, f.y) * (0.6 + 0.4 * step(0.5, fract(q.x * 2.0)));
		room = tube * (0.32 + 0.68 * ceiling);
	} else if (lobby > 0.5) {
		// One hall: floor, ceiling and back wall (its ends are past the glass's own ends).
		vec3 p = vec3(uv.x, uv.y - lobby_room.x, 0.0);
		vec3 size = vec3(1.0, lobby_room.y - lobby_room.x, lobby_room.z);
		vec4 h = room_hit(p, rd, size, false);
		float hy = h.y / size.y;
		vec2 dl = fract(vec2(h.x / 2.4, h.z / 2.4)) - 0.5;
		if (h.w > 0.5 && h.w < 1.5) {
			// Ceiling: a grid of round downlights in a pale plaster.
			float dot_l = 1.0 - smoothstep(0.08, 0.13, length(dl));
			room = tube * (0.28 + 4.0 * dot_l);
		} else if (h.w > 1.5) {
			// Stone floor, the downlights' pools on it and their reflections.
			float pool = exp(-dot(dl, dl) * 9.0);
			float tiles = 0.9 + 0.1 * step(0.5, fract(h.x * 0.5 + 0.5 * floor(h.z * 0.5)));
			room = tube * (0.30 + 0.55 * pool) * tiles;
		} else {
			// Back wall: lit from the ceiling, a lit panel high up (a plain wall board, no emblem),
			// the reception counter along its foot, darker under its top.
			room = tube * (0.30 + 0.35 * hy);
			float panel = step(abs(fract(h.x / 9.0) - 0.5), 0.17) * step(0.48, hy) * step(hy, 0.66);
			room = mix(room, vec3(0.75, 0.82, 0.95) * 1.6, panel);
			float counter = step(h.y, 1.1) * step(abs(fract(h.x / 9.0) - 0.5), 0.3);
			room = mix(room, tube * mix(0.06, 0.55, smoothstep(0.95, 1.1, h.y)), counter);
		}
		// Depth: what is further in gets a little less of the light.
		room *= 1.0 - 0.25 * clamp(length(h.xyz - p) / 14.0, 0.0, 1.0);
	} else {
		// An office: two bays wide, a storey high, OFFICE_DEPTH deep.
		vec2 cw = vec2(cell.x * 2.0, cell.y);
		vec2 fo = fract(vec2(q.x * 0.5, q.y));
		vec3 p = vec3(fo.x * cw.x, fo.y * cw.y, 0.0);
		vec4 h = room_hit(p, rd, vec3(cw, office_depth), true);
		float hy = h.y / cw.y;
		if (h.w > 0.5 && h.w < 1.5) {
			// Ceiling: lay-in tiles, every other one a lit panel.
			vec2 c = fract(vec2(h.x / 1.2, h.z / 1.2));
			float panel = step(0.5, fract(floor(h.z / 1.2) * 0.5)) * step(0.1, c.x) * step(c.x, 0.9) * step(0.15, c.y) * step(c.y, 0.85);
			room = tube * (0.35 + 2.6 * panel);
		} else if (h.w > 1.5) {
			// Carpet, lighter under the panels.
			room = tube * (0.10 + 0.08 * step(0.5, fract(floor(h.z / 1.2) * 0.5)));
		} else {
			// Walls lit from above, a desk and monitor line along their foot, now and then a
			// cabinet or a pinboard.
			room = tube * (0.18 + 0.30 * hy * hy);
			float desk = smoothstep(0.19, 0.2, hy) - smoothstep(0.27, 0.28, hy);
			room *= 1.0 - 0.55 * desk * step(0.3, fract(r * 9.1));
			float screen = step(0.29, hy) * step(hy, 0.37) * step(abs(fract(h.x * 0.6 + r) - 0.5), 0.12);
			room = mix(room, vec3(0.45, 0.6, 0.9) * 0.9, screen * step(h.w, 0.5) * step(0.4, fract(r * 3.3)));
		}
		room *= 1.0 - 0.35 * clamp(h.z / office_depth, 0.0, 1.0);
	}
	// A blind drawn to its own height in some offices, glowing with the room behind it.
	if (lobby < 0.5) {
		float blind = 1.0 - fract(r * 3.71) * 0.55;
		float has_blind = step(0.4, fract(r * 5.3));
		room = mix(room, tube * 0.22, step(blind, f.y) * has_blind);
	}
	room *= (0.55 + 0.45 * fract(r * 13.7)) * (1.0 - mull);
	float night = lamp_factor * night_energy * (lobby > 0.5 ? 2.2 : 1.0);
	float day = lobby > 0.5 ? 0.12 : 0.0;
	vec3 emit = room * lit * (night + day * (1.0 - lamp_factor));
	emit += sky * (0.03 + 0.97 * fres) * mirror * (1.0 - 0.7 * lamp_factor) * (1.0 - mull);
	ALBEDO = cs_out(albedo);
	METALLIC = 0.2;
	ROUGHNESS = mix(0.05, 0.4, mull);
	SPECULAR = 0.6;
	EMISSION = cs_out(emit);
}
