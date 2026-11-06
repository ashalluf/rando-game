// Rando Pier's deck (PierDay.deck_material(); `PIER_DAY=0` keeps the old plank photo): weathered
// boards laid ACROSS the pier, worked out per pixel from the mesh's own coordinates (VERTEX is the
// park frame: x along the pier, out to sea negative, z across it). Each board BOARD_W wide with a
// dark gap, butt joints staggered per board, its own tone (silver-grey weathered timber, a darker
// one, the odd newer replacement), grain along it, nail pairs over the joists, a slight cup; a
// polished wear path down the promenade, grime along the rail (`outline`, PierPark.OUTLINE), spills
// and gum. Everything under a pixel fades to its average (no moire at grazing angles). The deck's
// side faces (its fascia) are old dark timber. Linear on both renderers (color_space.gdshaderinc).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

global uniform float road_wetness;

uniform float board_w = 0.145;
uniform float gap_w = 0.011;
uniform float board_len = 4.9;
uniform float joist = 0.61;
uniform vec2 outline[12];
uniform int outline_count = 12;
// Linear colours.
uniform vec3 wood_grey = vec3(0.165, 0.142, 0.115);
uniform vec3 wood_dark = vec3(0.098, 0.080, 0.062);
uniform vec3 wood_new = vec3(0.190, 0.118, 0.068);
uniform vec3 gap_color = vec3(0.012, 0.010, 0.009);

varying vec3 v_local;
varying vec3 v_wnormal;

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Distance to the nearest segment of the rail outline.
float rail_dist(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < 11; i++) {
		if (i + 1 >= outline_count) {
			break;
		}
		vec2 a = outline[i];
		vec2 b = outline[i + 1];
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		d = min(d, length(p - a - ab * t));
	}
	return d;
}

// The share of a pixel `px` wide covered by a line `w` wide centred at distance `d` (box filter).
float line_cover(float d, float w, float px) {
	float lo = d - 0.5 * px;
	float hi = d + 0.5 * px;
	float half_w = 0.5 * w;
	return clamp((min(hi, half_w) - max(lo, -half_w)) / max(px, 1e-5), 0.0, 1.0);
}

void vertex() {
	v_local = VERTEX;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = v_local.xz;
	vec3 alb;
	float rough = 0.86;
	float wet = clamp(road_wetness, 0.0, 1.0);
	if (v_wnormal.y < 0.6) {
		// The fascia: old dark timber with vertical seams every board's width.
		float pxs = max(fwidth(UV.x), 1e-4);
		float seam = line_cover(abs(fract(UV.x / 0.2 + 0.5) - 0.5) * 0.2, 0.012, pxs);
		float grain = mix(vnoise(vec2(UV.x * 40.0, UV.y * 3.0)), 0.5, smoothstep(0.01, 0.05, pxs));
		alb = mix(wood_dark, wood_grey, 0.35 + 0.3 * grain) * (1.0 - 0.6 * seam);
		ALBEDO = cs_out(alb * (1.0 - 0.35 * wet));
		ROUGHNESS = rough;
		SPECULAR = 0.4;
	} else {
		float pxx = max(fwidth(p.x), 1e-5);
		float pxz = max(fwidth(p.y), 1e-5);
		float fx = p.x / board_w;
		float bi = floor(fx);
		float fa = fract(fx);
		float across = fa * board_w;
		float hb = h21(vec2(bi, 7.1));
		// Butt joints along the board, staggered per board.
		float fz = (p.y + hb * board_len) / board_len;
		float bj = floor(fz);
		vec2 bid = vec2(bi, bj);
		float h = h21(bid + vec2(13.7, 2.9));
		float h2 = h21(bid + vec2(3.3, 41.2));
		// The board's tone.
		vec3 tone = mix(wood_dark, wood_grey, 0.45 + 0.55 * h2);
		if (h < 0.18) {
			tone = mix(wood_dark, wood_grey, 0.15 * h2);
		} else if (h > 0.93) {
			tone = mix(wood_new, wood_grey, 0.35 * h2);
		}
		tone *= 0.9 + 0.2 * h21(bid + vec2(9.0, 5.0));
		// Grain: long streaks along the board, faded once a streak is under a pixel.
		float gfade = smoothstep(0.004, 0.03, pxx);
		float grain = vnoise(vec2(across * 140.0 + h * 50.0, p.y * 1.4)) * 0.6 + vnoise(vec2(across * 420.0, p.y * 5.0)) * 0.4;
		grain = mix(grain, 0.5, gfade);
		alb = tone * (0.82 + 0.36 * grain);
		// Grey weathering: open grain silvers in patches.
		float silver = smoothstep(0.45, 0.85, vnoise(p * vec2(0.9, 0.35) + vec2(h * 7.0, 0.0)));
		alb = mix(alb, vec3(dot(alb, vec3(0.33))) * 1.12, 0.45 * silver);
		// The polished wear path down the promenade (the main pier, x < 0, |z| under 12).
		float on_main = step(p.x, 0.5) * (1.0 - smoothstep(10.0, 12.0, abs(p.y)));
		float path = exp(-pow(p.y / 5.5, 2.0)) * on_main;
		path *= 0.65 + 0.35 * vnoise(p * 0.15);
		alb *= 1.0 - 0.10 * path;
		rough -= 0.10 * path;
		// Grime gathered along the rail and in the corners.
		float rd = rail_dist(p);
		float grime = 1.0 - smoothstep(0.1, 1.6, rd);
		alb = mix(alb, alb * vec3(0.55, 0.52, 0.48), 0.6 * grime);
		// Spills and old stains.
		float st = vnoise(p * 0.7 + vec2(31.0, 17.0)) * 0.65 + vnoise(p * 2.3) * 0.35;
		alb *= 1.0 - 0.3 * smoothstep(0.68, 0.82, st);
		// Gum: a few dark dots per square metre, faded to their mean under a pixel.
		vec2 gc = floor(p * 2.0);
		float gh = h21(gc + vec2(5.0, 19.0));
		vec2 gp = (gc + 0.2 + 0.6 * vec2(h21(gc + 1.7), h21(gc + 8.3))) / 2.0;
		float gum = step(0.86, gh) * (1.0 - smoothstep(0.012, 0.022, length(p - gp)));
		gum = mix(gum, 0.003, smoothstep(0.01, 0.03, max(pxx, pxz)));
		alb = mix(alb, vec3(0.03, 0.03, 0.035), gum);
		// Nails: a pair near each board's edges over every joist.
		float jz = abs(fract(p.y / joist) - 0.5) * joist;
		float nx = min(abs(across - 0.028), abs(across - (board_w - 0.028)));
		float nail = 1.0 - smoothstep(0.004, 0.007, length(vec2(nx, jz - 0.5 * joist)));
		nail = mix(nail, 0.0, smoothstep(0.004, 0.012, max(pxx, pxz)));
		alb = mix(alb, vec3(0.05, 0.04, 0.035), 0.8 * nail);
		// The gaps between boards and the butt joints, box-filtered by the pixel.
		float dg = min(across, board_w - across);
		float gap = line_cover(dg, gap_w * 2.0, pxx);
		float jd = min(fract(fz), 1.0 - fract(fz)) * board_len;
		float joint = line_cover(jd, 0.012, pxz) * 0.8;
		float dark = max(gap, joint);
		// Edges of the boards catch a little less light (rounded, dirtier).
		float edge = (1.0 - smoothstep(0.004, 0.02, dg)) * (1.0 - smoothstep(0.004, 0.02, pxx));
		alb *= 1.0 - 0.25 * edge;
		alb = mix(alb, gap_color, dark);
		// Wet: darker, a film in the wear path.
		alb *= 1.0 - 0.4 * wet;
		rough = mix(rough, 0.25, wet * 0.8);
		// A slight cup across each board and a tilt per board, faded under a pixel.
		float tfade = 1.0 - smoothstep(0.03, 0.12, pxx);
		float cup = (fa - 0.5) * 0.10;
		vec3 nw = normalize(v_wnormal + vec3((cup + (h2 - 0.5) * 0.05) * tfade, 0.0, (h - 0.5) * 0.03 * tfade));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		ALBEDO = cs_out(alb);
		ROUGHNESS = clamp(rough, 0.05, 1.0);
		SPECULAR = 0.35;
	}
}
