shader_type spatial;
render_mode cull_back;

// Window glass on the replica's houses (ReplicaBuilder). A pane is a quad with UV 0..1 across it
// and a per-window random in COLOR.a (COLOR.rgb is the blind / curtain colour).
//
// What a house window looks like from the street is mostly two things: the sky and the street
// mirrored in it, strongest at a grazing angle, and a dark room behind it with a blind or a
// curtain drawn to some height. So: a Schlick fresnel mirror whose sky part is EMITTED (a
// reflection does not depend on the light falling on the pane - carried in the albedo, a pane in
// shade went black, the same lesson as building.gdshader), a cheap one-plane parallax room, a
// blind at its own height, and at night a share of the rooms lit warm.

global uniform float night_factor;
global uniform vec4 sky_tint;
global uniform float city_hour;
global uniform float lamp_factor;
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/house_nights.gdshaderinc"
#ifndef WINDOW_INTERIORS_DECLARED
#define WINDOW_INTERIORS_DECLARED
global uniform float window_interiors;
#endif

// HouseNights (UV2.x = the house key + 1; 0 on panes that carry none, which keep the old look):
// the whole house's night from one integer - dark houses, a lamp tone per house, rooms behind
// sheers or blinds, a TV's flicker - the same rolls building_lod.gdshader gives its far box.
uniform float night_energy = 1.35;
uniform float tv_energy = 1.1;

// Share of windows lit after dark.
uniform float lit_share = 0.42;
uniform vec3 lit_color : source_color = vec3(1.0, 0.80, 0.52);
uniform float lit_energy = 1.1;
// How deep the fake room is behind the pane (metres of parallax), and its dim colour.
uniform float room_depth = 2.6;
uniform vec3 room_color : source_color = vec3(0.10, 0.09, 0.08);
// How much of the mirror is emitted rather than lit.
uniform float reflect_emit = 0.55;
// The street half of the mirror (below the horizon): warm grey.
uniform vec3 street_color : source_color = vec3(0.32, 0.31, 0.29);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 wtan;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wtan = normalize((MODEL_MATRIX * vec4(TANGENT.xyz, 0.0)).xyz);
}


void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 R = reflect(-V, N);
	// The mirror: sky above the horizon, the street under it.
	vec3 sky = sky_tint.rgb * mix(0.9, 1.25, clamp(R.y, 0.0, 1.0));
	vec3 mirror = mix(street_color, sky, smoothstep(-0.08, 0.12, R.y));
	// The room: step the view ray back by room_depth and read where it lands on the back wall,
	// in the pane's own UV. Floor darker than ceiling, a blind across the top.
	float rnd = COLOR.a;
	vec3 T = normalize(wtan - N * dot(wtan, N));
	vec3 B = cross(N, T);
	vec2 into = vec2(dot(-V, T), dot(-V, B)) / max(ndv, 0.2);
	vec2 back = UV + into * (room_depth / 2.2) * vec2(0.5, -0.5);
	float inside = step(0.0, back.x) * step(back.x, 1.0) * step(0.0, back.y) * step(back.y, 1.0);
	vec3 room = room_color * mix(0.55, 1.3, clamp(1.0 - back.y, 0.0, 1.0)) * mix(0.6, 1.0, inside);
	float blind = 0.15 + 0.6 * fract(rnd * 7.31);
	float under_blind = step(UV.y, blind);
	room = mix(room, COLOR.rgb * 0.45, under_blind);
	float lit = step(rnd, lit_share) * clamp(night_factor, 0.0, 1.0);
	vec3 lit_room = lit_color * mix(0.7, 1.2, fract(rnd * 13.7)) * mix(1.0, 0.8, under_blind);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	if (UV2.x < 0.5) {
		ALBEDO = mix(room, vec3(0.0), fres) * (1.0 - lit);
		EMISSION = mirror * fres * reflect_emit * (1.0 - 0.7 * night_factor) + lit_room * lit_energy * lit * (1.0 - fres * 0.6);
	} else {
		// ------------------------------------------------------------- HouseNights -----
		int key = int(UV2.x - 1.0 + 0.5);
		float nf = clamp(night_factor, 0.0, 1.0);
		float share = hn_share(key, city_hour);
		bool on_room = rnd < share;
		// One room in a TV house: the lowest-rolled lit pane of the house is the TV room.
		bool tv_room = on_room && hn_tv(key) && rnd < share * 0.3;
		vec3 tone = hn_tone(hn_tone_index(key));
		// Room to room the bulbs differ a little (a lamp shade, a warmer bedside lamp).
		tone = mix(tone, hn_tone(int(fract(rnd * 31.7) * 4.0)), 0.25 * fract(rnd * 5.3));
		// The room traced behind the pane (back wall at room_depth): a lamp's warm hotspot on the
		// back wall, the ceiling lit off it, a dark sofa line and a picture frame. All LINEAR.
		vec2 bp = clamp(back, vec2(0.0), vec2(1.0));
		float lamp_u = 0.2 + 0.6 * fract(rnd * 17.3);
		float hot = exp(-pow((bp.x - lamp_u) * 2.6, 2.0) - pow((bp.y - 0.55) * 2.0, 2.0));
		float ceil_l = smoothstep(0.35, 0.0, back.y) * 0.5;
		float sofa = step(0.72, bp.y) * step(abs(bp.x - 0.5 + 0.2 * (fract(rnd * 3.1) - 0.5)), 0.34);
		float frame = step(abs(bp.x - (1.0 - lamp_u)), 0.13) * step(abs(bp.y - 0.38), 0.10);
		frame *= 1.0 - step(abs(bp.x - (1.0 - lamp_u)), 0.10) * step(abs(bp.y - 0.38), 0.07);
		float wall_l = (0.30 + 1.1 * hot + ceil_l) * mix(0.55, 1.0, inside);
		wall_l *= 1.0 - 0.75 * sofa - 0.5 * frame;
		// Somebody walking across the room now and then (window_interiors: a few seconds every
		// 10-30 s): a dark figure between the lamp and the back wall, head and shoulders.
		if (window_interiors > 0.5 && fract(rnd * 23.1) < 0.45) {
			float period = 10.0 + 20.0 * fract(rnd * 41.3);
			float ph = (TIME + 97.0 * fract(rnd * 3.7)) / period;
			float s = fract(ph) * period / 3.2;
			if (s < 1.0) {
				float fx = mix(-0.25, 1.25, mod(floor(ph), 2.0) < 0.5 ? s : 1.0 - s);
				float dx = abs(back.x - fx);
				float body = step(dx, 0.11) * step(0.42, back.y);
				float headk = step(length(vec2(dx, (back.y - 0.30) * 1.3)), 0.075);
				wall_l *= 1.0 - 0.82 * max(body, headk);
			}
		}
		vec3 room_lit = tone * wall_l;
		if (tv_room) {
			vec3 tv = hn_tv_light(key, TIME);
			room_lit = tone * wall_l * 0.25 + tv * (0.35 + 0.9 * exp(-pow((bp.x - 0.5) * 2.0, 2.0))) * tv_energy;
		}
		// What hangs at the glass: sheers drawn across with a gap (most), a slatted blind, or
		// nothing. A sheer softens the room behind it to its average and glows itself.
		float cover = fract(rnd * 11.9);
		float sheer = 0.0;
		float slats = 0.0;
		// The window-interiors pass adds lined drapes drawn to the sides and roller blinds.
		float drapes = 0.0;
		float roller = 0.0;
		float sheer_edge = window_interiors > 0.5 ? 0.36 : 0.55;
		float slat_edge = window_interiors > 0.5 ? 0.70 : 0.8;
		if (cover < sheer_edge) {
			float gap = 0.18 + 0.3 * fract(rnd * 2.7);
			float folds = 0.7 + 0.3 * sin(UV.x * 46.0 + rnd * 9.0);
			sheer = (1.0 - step(abs(UV.x - 0.5), gap * 0.5)) * folds;
		} else if (cover < 0.56) {
			float a = 0.12 + 0.3 * fract(rnd * 6.1);
			drapes = (1.0 - step(a, UV.x) * step(UV.x, 1.0 - a)) * (0.72 + 0.28 * cos(UV.x * 60.0 + rnd * 7.0));
		} else if (cover < slat_edge) {
			float drop = 0.35 + 0.55 * fract(rnd * 4.9);
			slats = step(UV.y, drop) * (0.55 + 0.45 * step(0.25, fract(UV.y * 22.0)));
		} else if (cover < 0.84) {
			float drop = 0.25 + 0.6 * fract(rnd * 8.3);
			roller = step(UV.y, drop) * (UV.y > drop - 0.02 ? 0.55 : 1.0);
		}
		vec3 avg = tv_room ? hn_tv_light(key, TIME) * 0.45 * tv_energy : tone * 0.62;
		vec3 behind = mix(room_lit, avg * 0.9, clamp(sheer, 0.0, 1.0));
		behind = mix(behind, avg * 0.5 * slats, step(0.01, slats));
		// Lined drapes let a sliver through; a roller blind glows its own colour.
		behind = mix(behind, COLOR.rgb * avg * 0.18 * drapes, step(0.01, drapes));
		behind = mix(behind, mix(avg, COLOR.rgb * avg * 1.6, 0.5) * 0.55 * roller, step(0.01, roller));
		float lit_n = (on_room ? 1.0 : 0.0) * nf;
		vec3 em = behind * night_energy * lit_n * (1.0 - fres * 0.6);
		// An unlit room at night: the curtain or blind faintly against a dark room.
		vec3 dark_room = room * mix(1.0, 0.35, nf);
		dark_room = mix(dark_room, COLOR.rgb * 0.08, max(clamp(sheer, 0.0, 1.0), slats) * nf);
		// By day the fabric at the glass catches the daylight.
		dark_room = mix(dark_room, COLOR.rgb * mix(0.55, 0.06, nf) * max(drapes, 0.0), step(0.01, drapes));
		dark_room = mix(dark_room, COLOR.rgb * mix(0.62, 0.07, nf) * roller, step(0.01, roller));
		ALBEDO = mix(mix(dark_room, vec3(0.0), fres), vec3(0.0), lit_n);
		EMISSION = mirror * fres * reflect_emit * (1.0 - 0.7 * nf) + hn_lit(em);
	}
}
