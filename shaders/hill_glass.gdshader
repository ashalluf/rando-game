shader_type spatial;
render_mode cull_back;

// The glass walls of the hillside houses (HillHomeKit / HillHomeBuild): floor-to-ceiling panes
// whose UV is in METRES (x along the pane, y up from the storey's floor), so the room behind them
// is traced at its real size whatever the pane's width - house_glass.gdshader maps one parallax
// room onto a pane's 0..1 UV, which on a 12 m glass wall is one smeared room.
//
// Per pixel: the view ray is stepped into a box room (bays BAY wide along the wall, `depth` deep,
// `ceiling` high) and shaded where it lands - an oak or stone floor with a rug, a pale ceiling with
// recessed downlights, side walls, a back wall with a picture, a low sofa, a coffee table and a
// floor lamp in most bays (slab tests, so they have true parallax), a sheer curtain drawn across
// some bays. By day the room is lit by the sky through the glass, falling off inward; after dark
// most rooms are lit warm from the downlights and the lamp, which is what makes a hillside
// twinkle from the basin. The mirror is a Schlick fresnel whose sky part is EMITTED (a reflection
// does not depend on the light falling on the pane; carried in the albedo a pane in shade went
// black) - the renderer's own reflections add to it on Forward+.
// COLOR.rgb is the room's tone (sRGB as written; vertex colours arrive raw on both renderers),
// COLOR.a a per-pane random. Colours are worked in linear (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec4 sky_tint;

// Share of the rooms lit after dark (a hillside house is a show house: most of it).
uniform float lit_share = 0.82;
// The light in a lit room (linear) and how bright it reads through the glass.
uniform vec3 lit_color = vec3(1.0, 0.72, 0.42);
uniform float lit_energy = 2.4;
// The room: bay width along the wall, depth, ceiling height (metres).
uniform float bay = 4.6;
uniform float depth = 5.2;
uniform float ceiling = 2.85;
// How much of the sky reaches the room by day, and how much of the mirror is emitted.
uniform float day_light = 0.34;
uniform float reflect_emit = 0.6;
// The street / hillside half of the mirror (below the horizon), linear.
uniform vec3 ground_color = vec3(0.07, 0.065, 0.055);
// Past this distance the furniture is under a pixel: the room is drawn as its average.
uniform float detail_far = 140.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 wtan;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wtan = normalize((MODEL_MATRIX * vec4(TANGENT.xyz, 0.0)).xyz);
}


float h11(float p) {
	return fract(sin(p * 127.1 + 31.7) * 43758.5453);
}


// Ray (o, d) against the box lo..hi: the entry distance, or -1.
float slab(vec3 o, vec3 d, vec3 lo, vec3 hi) {
	vec3 inv = 1.0 / d;
	vec3 t0 = (lo - o) * inv;
	vec3 t1 = (hi - o) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float a = max(max(tn.x, tn.y), tn.z);
	float b = min(min(tf.x, tf.y), tf.z);
	return (b > max(a, 0.0)) ? a : -1.0;
}


void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 N = normalize(wnrm);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 R = reflect(-V, N);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	vec3 mirror = mix(ground_color * (0.4 + 0.6 * dot(sky, vec3(0.33))), sky * mix(0.9, 1.2, clamp(R.y, 0.0, 1.0)), smoothstep(-0.06, 0.1, R.y));
	float rnd = COLOR.a;
	vec3 tone = cs_srgb_to_linear(COLOR.rgb);

	// Room space: x along the wall (UV.x), y up (UV.y), z into the room.
	vec3 T = normalize(wtan - N * dot(wtan, N));
	vec3 d = vec3(dot(-V, T), -V.y, dot(-V, -N));
	d.z = max(d.z, 0.02);
	vec3 o = vec3(UV.x, UV.y, 0.0);
	float bi = floor(UV.x / bay);
	float x0 = bi * bay;
	float x1 = x0 + bay;
	float br = h11(bi * 7.13 + rnd * 91.7);
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float detail = 1.0 - smoothstep(detail_far * 0.6, detail_far, dist);

	// The room's shell.
	float t = depth / d.z;
	int surf = 0; // 0 back wall, 1 floor, 2 ceiling, 3 side wall
	if (d.y < 0.0) {
		float tf = -o.y / d.y;
		if (tf < t) { t = tf; surf = 1; }
	} else if (d.y > 0.0) {
		float tc = (ceiling - o.y) / d.y;
		if (tc < t) { t = tc; surf = 2; }
	}
	float ts = (d.x > 0.0 ? (x1 - o.x) : (x0 - o.x)) / (abs(d.x) < 1e-4 ? 1e-4 * sign(d.x + 1e-6) : d.x);
	if (ts > 0.0 && ts < t) { t = ts; surf = 3; }
	vec3 p = o + d * t;
	vec3 alb;
	float lx = (p.x - x0) / bay;
	if (surf == 1) {
		// Floor: wide boards (or stone), a rug under the sofa.
		float boards = 0.92 + 0.08 * h11(floor(p.x / 0.22) + bi * 3.1);
		alb = tone * boards * 0.75;
		float rug = step(0.18, lx) * step(lx, 0.82) * step(depth - 3.3, p.z) * step(p.z, depth - 0.6);
		alb = mix(alb, vec3(0.62, 0.58, 0.52), rug * 0.8 * step(0.35, br) * detail);
	} else if (surf == 2) {
		alb = vec3(0.82, 0.81, 0.79);
	} else if (surf == 3) {
		alb = vec3(0.74, 0.72, 0.69) * mix(0.85, 1.05, br);
	} else {
		alb = vec3(0.78, 0.76, 0.72) * mix(0.8, 1.05, br);
		// A picture on the back wall.
		float art = step(0.3, lx) * step(lx, 0.7) * step(1.15, p.y) * step(p.y, 2.05) * step(br, 0.7);
		vec3 art_c = cs_srgb_to_linear(vec3(0.55 + 0.4 * h11(bi + 3.0), 0.35 + 0.4 * h11(bi + 5.0), 0.25 + 0.5 * h11(bi + 9.0)));
		alb = mix(alb, art_c, art * detail);
	}
	// Furniture: a low sofa against the back, a coffee table, a floor lamp.
	float hit_t = t;
	bool lamp_hit = false;
	if (br < 0.75 && detail > 0.01) {
		float ts2 = slab(o, d, vec3(x0 + 0.7, 0.0, depth - 1.15), vec3(x1 - 0.7, 0.78, depth - 0.25));
		if (ts2 > 0.0 && ts2 < hit_t) {
			hit_t = ts2;
			vec3 q = o + d * ts2;
			vec3 fab = mix(vec3(0.70, 0.67, 0.62), vec3(0.16, 0.16, 0.17), step(0.45, h11(bi * 2.3)));
			alb = fab * (q.y > 0.74 ? 1.0 : 0.82);
		}
		float tt = slab(o, d, vec3(x0 + 1.5, 0.0, depth - 2.5), vec3(x1 - 1.5, 0.42, depth - 1.75));
		if (tt > 0.0 && tt < hit_t) {
			hit_t = tt;
			alb = vec3(0.16, 0.10, 0.07);
		}
		float lxp = x0 + 0.45;
		float tl = slab(o, d, vec3(lxp - 0.2, 1.25, depth - 0.65), vec3(lxp + 0.2, 1.6, depth - 0.25));
		if (tl > 0.0 && tl < hit_t) {
			hit_t = tl;
			alb = vec3(0.9, 0.86, 0.78);
			lamp_hit = true;
		}
	}
	p = o + d * hit_t;
	float depth_k = clamp(p.z / depth, 0.0, 1.0);

	// Light. By day the sky through the glass, weaker inward; at night the room's own lights.
	float day = 1.0 - clamp(night_factor, 0.0, 1.0);
	vec3 day_l = sky * day_light * mix(1.0, 0.42, depth_k) * day;
	float lit = step(rnd * 0.6 + br * 0.4, lit_share) * clamp(max(night_factor, lamp_factor), 0.0, 1.0);
	// Downlights in a grid on the ceiling: pools on the floor and walls under them.
	vec2 cell = vec2(fract(p.x / 1.5) - 0.5, fract(p.z / 1.6) - 0.5);
	float pool = exp(-dot(cell, cell) * 7.0);
	float wash = surf == 2 ? 0.35 : mix(0.6, 1.0, pool * (surf == 1 ? 1.0 : 0.6)) * mix(1.0, 0.75, p.y / ceiling);
	vec3 night_l = lit_color * lit_energy * wash * lit;
	vec3 room = alb * (day_l + night_l);
	if (surf == 2 && hit_t == t) {
		// The downlights themselves.
		float spot = 1.0 - smoothstep(0.05, 0.09, length(cell * vec2(1.5, 1.6)));
		room += lit_color * 4.0 * spot * lit * detail;
	}
	if (lamp_hit) {
		room += lit_color * 2.6 * lit;
	}
	// A sheer curtain drawn across a share of the bays, glowing when the room is lit.
	float curtain = step(0.78, h11(bi * 4.7 + rnd * 13.0));
	room = mix(room, vec3(0.86, 0.83, 0.77) * (day_l * 1.6 + lit_color * lit_energy * 0.75 * lit), curtain * 0.7);
	// Under a pixel the room is its average.
	vec3 avg = tone * 0.6 * (day_l + lit_color * lit_energy * 0.8 * lit);
	room = mix(avg, room, detail);
	// Mullion-free panes are a single sheet: a faint edge darkening at the bay lines reads as the
	// silicone joint between them.
	float joint = 1.0 - 0.5 * (1.0 - smoothstep(0.0, 0.03, min(lx, 1.0 - lx) * bay)) * detail;

	ALBEDO = cs_out(vec3(0.015));
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = cs_out((room * (1.0 - fres) * 0.92 * joint) + mirror * fres * reflect_emit * (1.0 - 0.75 * night_factor));
}
