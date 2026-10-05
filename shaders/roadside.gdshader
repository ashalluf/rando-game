shader_type spatial;
render_mode cull_back;

// Roadside commerce (scripts/world/roadside.gd, RoadsideKit): gas stations, car washes, auto and
// tyre shops, the Googie coffee shop, drive-thrus and the giant-donut / giant-cup stands. ONE
// material for all of it: each FULL chunk's pads are one mesh on it, and the repeated pieces
// (dispensers, vacuum stations, tyres, menu boards) one MultiMesh a kind on it.
//
// * Vertex colour alpha says what a face is: the code is round(alpha * 20) (RoadsideKit.K_*),
//   so 8-bit vertex colours keep it. RGB is the colour, authored sRGB.
// * UV2 is (roughness, metallic) on ordinary parts. On a traced shop window it is (room depth in
//   metres, room kind), on an LED price digit (digit 0-9 or 10 blank, 0).
// * UV is metres on solid parts. A shop window's UV.y is metres above the room's floor; a menu
//   board, a digit and a printed face are 0..1 over the face.
// * Colour space: worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform vec4 sky_tint;
global uniform float road_wetness;

// A lightbox face (canopy fascia, pole sign cabinet, menu board): by day the printed face with a
// little glow, after dark lit from behind.
uniform float glow_day = 0.22;
uniform float glow_night = 1.5;
// The canopy's recessed LED panels: what makes a forecourt the brightest thing on a street.
uniform float soffit_day = 0.9;
uniform float soffit_night = 7.5;
// A shop seen through its glass: how bright the room is by day (it is darker than outside) and
// after dark (it is the brightest thing on the pad).
uniform float room_day = 0.38;
uniform float room_night = 1.9;
// How much of the sky a shop window mirrors, emitted (a reflection does not depend on the light
// falling on the pane).
uniform float glass_mirror = 0.55;
// LED price digits and screens.
uniform float led_night = 6.0;
uniform float led_day = 1.6;
uniform float screen_glow = 1.2;
// Neon tubes and marquee bulbs.
uniform float neon_day = 0.6;
uniform float neon_night = 9.0;
uniform float bulb_day = 0.25;
uniform float bulb_night = 7.0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_code;
varying vec3 v_paint;
varying float v_seed;

float rs_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rs_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rs_hash(i), rs_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rs_hash(i + vec2(0.0, 1.0)), rs_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float rs_fbm(vec2 p) {
	return rs_noise(p) * 0.55 + rs_noise(p * 2.13 + 7.1) * 0.3 + rs_noise(p * 4.7 + 3.3) * 0.15;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_code = COLOR.a;
	// A MultiMesh piece's brand paint (INSTANCE_CUSTOM.rgb, sRGB) and a per-instance seed; on the
	// chunk mesh these are zero and nothing reads them (no face there carries the paint code).
	v_paint = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
}

// --- Seven-segment digit, uv 0..1 over the cell ---------------------------------------------

float rs_seg(vec2 uv, vec2 a, vec2 b) {
	vec2 lo = min(a, b) - vec2(0.07);
	vec2 hi = max(a, b) + vec2(0.07);
	vec2 d = max(lo - uv, uv - hi);
	return 1.0 - smoothstep(-0.015, 0.015, max(d.x, d.y));
}

float rs_digit(vec2 uv, int n) {
	if (n < 0 || n > 9) {
		return 0.0;
	}
	// Segments a (top) b c (right) d (bottom) e f (left) g (middle); uv.y down.
	const int MASK[10] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
	int m = MASK[n];
	vec2 p = vec2((uv.x - 0.5) * 1.25 + 0.5 - (0.5 - uv.y) * 0.12, uv.y);
	float on = 0.0;
	float x0 = 0.22;
	float x1 = 0.78;
	float y0 = 0.1;
	float y1 = 0.5;
	float y2 = 0.9;
	if ((m & 1) != 0) on = max(on, rs_seg(p, vec2(x0, y0), vec2(x1, y0)));
	if ((m & 2) != 0) on = max(on, rs_seg(p, vec2(x1, y0), vec2(x1, y1)));
	if ((m & 4) != 0) on = max(on, rs_seg(p, vec2(x1, y1), vec2(x1, y2)));
	if ((m & 8) != 0) on = max(on, rs_seg(p, vec2(x0, y2), vec2(x1, y2)));
	if ((m & 16) != 0) on = max(on, rs_seg(p, vec2(x0, y1), vec2(x0, y2)));
	if ((m & 32) != 0) on = max(on, rs_seg(p, vec2(x0, y0), vec2(x0, y1)));
	if ((m & 64) != 0) on = max(on, rs_seg(p, vec2(x0, y1), vec2(x1, y1)));
	return on;
}

// --- A printed menu panel: food shots in a grid with price strips -----------------------------

vec3 rs_menu(vec2 uv, float pick) {
	vec2 cell = vec2(uv.x * 4.0, uv.y * 3.0);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float h = rs_hash(id + pick * 7.3);
	vec3 ground = mix(vec3(0.12, 0.1, 0.09), vec3(0.85, 0.15, 0.1), step(0.55, rs_hash(vec2(pick, 2.0))));
	vec2 p = f - vec2(0.5, 0.42);
	float plate = 1.0 - smoothstep(0.3, 0.34, length(p * vec2(1.0, 1.8)));
	vec3 food = mix(vec3(0.55, 0.28, 0.1), vec3(0.9, 0.68, 0.32), rs_noise(f * 8.0 + id * 3.0));
	food = mix(food, vec3(0.25, 0.6, 0.18), step(0.8, rs_noise(f * 21.0 + h * 9.0)));
	food = mix(food, vec3(0.85, 0.15, 0.08), step(0.82, rs_noise(f * 17.0 + h * 5.0)));
	vec3 col = mix(ground * (0.85 + 0.15 * f.y), food, plate);
	// The price line under each shot and the menu's header band.
	float price = step(0.78, f.y) * step(0.18, f.x) * step(f.x, 0.82);
	col = mix(col, vec3(0.97, 0.95, 0.88), price * 0.85);
	float hdr = step(uv.y, 0.02) + step(0.985, uv.y);
	return mix(col, vec3(0.95, 0.75, 0.12), clamp(hdr, 0.0, 1.0));
}

// --- A shop seen through its window -----------------------------------------------------------
// The room behind the pane is traced: a back wall `depth` metres in, floor and ceiling, rows of
// fittings parallel to the glass (shelving gondolas, a counter), booth partitions at right angles
// to it (the diner), all lit. Kinds: 0 convenience store, 1 diner / coffee shop, 2 workshop bay,
// 3 fast-food dining room, 4 car wash tunnel, 5 donut / coffee stand.
// `s0` metres along the pane, `h0` metres above the floor; `ds dh dd` the ray (dd into the room).
vec3 rs_room(float s0, float h0, float ds, float dh, float dd, float depth, int kind, out float lit) {
	float H = kind == 2 || kind == 4 ? 4.6 : 3.1;
	float t = depth / max(dd, 1e-3);
	int surf = 0;  // 0 back wall, 1 floor, 2 ceiling, 3 a fitting's face, 4 its top, 5 a partition
	float fit_top = 0.0;
	if (dh < -1e-4) {
		float tf = -h0 / dh;
		if (tf < t) { t = tf; surf = 1; }
	} else if (dh > 1e-4) {
		float tc = (H - h0) / dh;
		if (tc < t) { t = tc; surf = 2; }
	}
	// Rows parallel to the glass: (depth into the room, height).
	vec2 rows[3];
	int nrows = 0;
	if (kind == 0) { rows[0] = vec2(2.2, 1.55); rows[1] = vec2(4.2, 1.55); rows[2] = vec2(6.2, 1.7); nrows = 3; }
	else if (kind == 1) { rows[0] = vec2(depth - 1.6, 1.05); nrows = 1; }
	else if (kind == 3) { rows[0] = vec2(depth - 1.8, 1.1); nrows = 1; }
	else if (kind == 5) { rows[0] = vec2(0.6, 1.05); nrows = 1; }
	else if (kind == 2) { rows[0] = vec2(depth - 0.8, 1.0); nrows = 1; }
	for (int i = 0; i < 3; i++) {
		if (i >= nrows) break;
		float tr = rows[i].x / max(dd, 1e-3);
		if (tr < t && rows[i].x < depth) {
			float hr = h0 + dh * tr;
			if (hr < rows[i].y) { t = tr; surf = 3; fit_top = rows[i].y; }
		}
		// The row's top: the ray coming down onto a counter or a shelf 40 cm deep.
		if (dh < -1e-4) {
			float tt = (rows[i].y - h0) / dh;
			float dt = dd * tt;
			if (tt > 0.0 && tt < t && dt > rows[i].x - 0.45 && dt < rows[i].x) { t = tt; surf = 4; fit_top = rows[i].y; }
		}
	}
	// The diner's booths: high-backed partitions every 1.9 m, 2 m deep from the glass.
	if (kind == 1 && abs(ds) > 1e-4) {
		float pitch = 1.9;
		float sb = (floor(s0 / pitch) + (ds > 0.0 ? 1.0 : 0.0)) * pitch;
		for (int k = 0; k < 3; k++) {
			float tp = (sb - s0) / ds;
			if (tp > t) break;
			if (tp > 0.0 && dd * tp < 2.0 && h0 + dh * tp < 1.2) { t = tp; surf = 5; break; }
			sb += ds > 0.0 ? pitch : -pitch;
		}
	}
	float s = s0 + ds * t;
	float h = h0 + dh * t;
	float d = dd * t;
	vec3 col;
	lit = 1.0;
	if (surf == 1) {
		// Floor: tiles (a checkerboard in the diner, big greys elsewhere, oily concrete in a bay).
		vec2 ft = vec2(s, d);
		if (kind == 1) {
			vec2 q = floor(ft / 0.45);
			col = mod(q.x + q.y, 2.0) < 0.5 ? vec3(0.08, 0.08, 0.08) : vec3(0.75, 0.72, 0.66);
		} else if (kind == 2 || kind == 4) {
			col = vec3(0.32, 0.31, 0.29) * (0.75 + 0.35 * rs_noise(ft * 0.9));
			col *= 1.0 - 0.4 * smoothstep(0.6, 0.9, rs_noise(ft * 0.35 + 4.0));
		} else {
			vec2 g = abs(fract(ft / 0.6) - 0.5);
			col = vec3(0.62, 0.6, 0.56) * (0.92 + 0.08 * rs_hash(floor(ft / 0.6)));
			col *= 1.0 - 0.25 * step(0.47, max(g.x, g.y));
		}
		lit = 0.75 - 0.25 * smoothstep(0.0, depth, d);
	} else if (surf == 2) {
		// Ceiling: lay-in tiles with lit panels (a store), pendants on a dark ceiling (the diner).
		vec2 ct = vec2(s, d);
		if (kind == 1 || kind == 5) {
			vec2 c = fract(ct / vec2(1.9, 1.6)) - 0.5;
			float pend = 1.0 - smoothstep(0.08, 0.12, length(c * vec2(1.9, 1.6)));
			col = mix(vec3(0.25, 0.18, 0.12), vec3(4.0, 3.2, 2.2), pend);
		} else {
			vec2 c = abs(fract(ct / vec2(2.4, 1.2)) - 0.5);
			float panel = step(c.x, 0.3) * step(c.y, 0.18) * step(0.5, rs_hash(floor(ct / vec2(2.4, 1.2))));
			col = mix(vec3(0.7, 0.7, 0.68), vec3(3.6, 3.6, 3.5), panel);
		}
		lit = 0.8;
	} else if (surf == 5) {
		// A booth's back: red or teal vinyl, buttoned, with a chrome cap.
		vec3 vinyl = step(0.5, rs_hash(vec2(floor(s / 1.9), 3.0))) > 0.5 ? vec3(0.55, 0.06, 0.05) : vec3(0.05, 0.38, 0.36);
		col = vinyl * (0.85 + 0.15 * step(0.5, fract(h * 6.0)));
		col = mix(col, vec3(0.9), step(1.12, h));
	} else if (surf == 3 || surf == 4) {
		if (kind == 0) {
			// Shelving: product facings in bands, a price rail under each shelf.
			float shelf = floor(h / 0.38);
			float fh = fract(h / 0.38);
			float item = floor(s / 0.22 + shelf * 3.1);
			float hh = rs_hash(vec2(item, shelf + fit_top * 3.0));
			vec3 prod = mix(vec3(0.5), 0.5 + 0.5 * cos(6.2831 * (hh + vec3(0.0, 0.33, 0.67))), 0.55);
			prod *= 0.55 + 0.5 * rs_hash(vec2(item, 7.0));
			col = mix(prod, vec3(0.8, 0.8, 0.78), step(fh, 0.12));
			col = surf == 4 ? vec3(0.7, 0.7, 0.68) : col;
		} else if (kind == 1 || kind == 3 || kind == 5) {
			// The counter: a laminate front with a chrome rail, its top lit; pastry cases on the stand.
			col = kind == 1 ? vec3(0.75, 0.55, 0.15) : (kind == 5 ? vec3(0.95, 0.85, 0.7) : vec3(0.6, 0.12, 0.08));
			col = mix(col, vec3(0.9, 0.9, 0.88), step(fit_top - 0.08, h));
			if (kind == 5 && surf == 3) {
				vec2 c = fract(vec2(s / 0.24, h / 0.2)) - 0.5;
				float ring = smoothstep(0.32, 0.26, length(c)) * step(0.1, length(c));
				col = mix(vec3(0.95, 0.95, 0.92), mix(vec3(0.75, 0.45, 0.2), vec3(0.95, 0.5, 0.65), step(0.5, rs_hash(floor(vec2(s / 0.24, h / 0.2))))), ring);
				lit = 1.4;
			}
		} else {
			// A workbench under a pegboard.
			col = vec3(0.35, 0.12, 0.08) * (0.85 + 0.15 * rs_noise(vec2(s * 3.0, h * 3.0)));
		}
	} else {
		// The back wall.
		if (kind == 0) {
			// Coolers: glass doors, lit from inside, bottles behind.
			float door = fract(s / 0.75);
			float frame = step(door, 0.06) + step(h, 0.25) + step(2.2, h);
			float hh = rs_hash(vec2(floor(s / 0.12), floor(h / 0.33)));
			vec3 bottles = mix(vec3(0.55), 0.5 + 0.5 * cos(6.2831 * (hh + vec3(0.0, 0.33, 0.67))), 0.6) * 1.1;
			col = mix(bottles, vec3(0.15, 0.15, 0.16), clamp(frame, 0.0, 1.0));
			col = mix(col, vec3(0.7, 0.7, 0.68), step(2.5, h));
			lit = 1.5 - 0.6 * step(2.2, h);
		} else if (kind == 1 || kind == 3) {
			// Back bar: a menu strip lit over the kitchen pass, steel below.
			float strip = step(1.9, h) * step(h, 2.5);
			col = mix(vec3(0.6, 0.58, 0.55), rs_menu(vec2(fract(s / 3.0), (h - 1.9) / 0.6), floor(s / 3.0)), strip);
			lit = 1.0 + strip * 0.8;
		} else if (kind == 4) {
			// The tunnel: wraparound brushes and curtains of coloured cloth in a row, foam on
			// them, the conveyor's lit sign strip along the top.
			float cell = floor(s / 1.6);
			float u = fract(s / 1.6);
			float hh = rs_hash(vec2(cell, 5.0));
			vec3 cloth = hh < 0.33 ? vec3(0.15, 0.45, 0.95) : (hh < 0.66 ? vec3(0.95, 0.3, 0.6) : vec3(0.98, 0.85, 0.2));
			float brush = smoothstep(0.1, 0.2, u) * smoothstep(0.9, 0.8, u) * step(0.3, h) * step(h, 3.0);
			float strands = 0.7 + 0.3 * rs_noise(vec2(s * 30.0, h * 2.0));
			vec3 foam = vec3(0.9, 0.92, 0.95) * step(0.72, rs_noise(vec2(s * 4.0, h * 3.0)));
			col = mix(vec3(0.3, 0.32, 0.34), mix(cloth * strands, foam, length(foam) > 0.1 ? 0.6 : 0.0), brush);
			float strip = step(3.4, h) * step(h, 3.7);
			col = mix(col, vec3(0.4, 0.8, 1.0) * 2.0, strip);
			lit = 1.3;
		} else if (kind == 2) {
			// Pegboard and tool chests in a bay.
			col = vec3(0.5, 0.45, 0.36) * (0.8 + 0.2 * step(0.5, fract(s * 4.0) * fract(h * 4.0) * 4.0));
			col = mix(col, vec3(0.6, 0.06, 0.04), step(h, 1.0) * step(0.5, fract(s / 3.0)));
		} else if (kind == 5) {
			// The stand: wire racks of trays, rings of glazed and plain dough in rows, a menu
			// strip above them.
			vec2 c = fract(vec2(s / 0.26, h / 0.24)) - 0.5;
			vec2 id = floor(vec2(s / 0.26, h / 0.24));
			float ring = smoothstep(0.36, 0.3, length(c)) * smoothstep(0.08, 0.14, length(c));
			vec3 glaze = mix(vec3(0.72, 0.45, 0.2), mix(vec3(0.95, 0.5, 0.65), vec3(0.35, 0.18, 0.1), step(0.6, rs_hash(id))), step(0.4, rs_hash(id + 3.0)));
			float racks = step(0.8, h) * step(h, 2.0);
			col = mix(vec3(0.85, 0.82, 0.76), mix(vec3(0.75, 0.75, 0.74), glaze, ring), racks);
			float strip = step(2.25, h) * step(h, 2.75);
			col = mix(col, rs_menu(vec2(fract(s / 2.5), (h - 2.25) / 0.5), floor(s / 2.5) + 9.0), strip);
			lit = 0.7;
		} else {
			col = vec3(0.8, 0.76, 0.7);
		}
		lit *= 0.9;
	}
	return col;
}

void fragment() {
	int code = int(round(v_code * 20.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	vec3 V = normalize(v_world - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	if (code == 20) {
		base = cs_srgb_to_linear(v_paint) * (0.95 + 0.05 * rs_noise(UV * 6.0 + v_seed * 17.0));
	} else if (code == 1) {
		// Brushed steel: grain along the panel, faded to its mean under a pixel.
		float fw = fwidth(UV.y) * 60.0;
		float g = mix(rs_noise(vec2(UV.x * 1.3, UV.y * 60.0)), 0.5, smoothstep(0.3, 1.0, fw));
		rough = clamp(rough + (g - 0.5) * 0.18, 0.08, 0.9);
		base *= 0.94 + 0.08 * g;
	} else if (code == 2) {
		// Poured concrete: joints every 4.5 m, mottle, oil drips and tyre scuffs where cars stand.
		vec2 j = abs(fract(UV / 4.5) - 0.5);
		float joint = smoothstep(0.497, 0.4995, max(j.x, j.y)) * (1.0 - smoothstep(0.0, 0.02, fwidth(UV.x)));
		float m = rs_fbm(UV * 0.6);
		base *= (0.82 + 0.3 * m) * (1.0 - 0.45 * joint);
		float oil = smoothstep(0.66, 0.82, rs_fbm(UV * 0.9 + 11.0)) * smoothstep(0.4, 0.7, rs_noise(UV * 0.25));
		base *= 1.0 - 0.45 * oil;
		rough = mix(rough, 0.35, oil * 0.6);
		rough = mix(rough, 0.12, clamp(road_wetness, 0.0, 1.0) * 0.8);
	} else if (code == 3) {
		// Painted stucco: a sand finish and soft weathering streaks under the parapet.
		float n = rs_noise(UV * 9.0);
		base *= 0.93 + 0.1 * n;
		base *= 1.0 - 0.07 * rs_noise(vec2(UV.x * 1.5, UV.y * 0.2));
	} else if (code == 4) {
		// A shop window: the sky mirrored by Fresnel, the room behind traced, lit after dark.
		vec3 N = normalize(v_wnormal);
		vec3 along = normalize(cross(vec3(0.0, 1.0, 0.0), N));
		float ds = dot(V, along);
		float dh = V.y;
		float dd = dot(V, -N);
		float s0 = dot(v_world, along);
		float lit;
		vec3 room = rs_room(s0, UV.y, ds, dh, max(dd, 0.05), max(UV2.x, 1.0), int(UV2.y + 0.5), lit);
		float fres = 0.04 + 0.96 * pow(1.0 - clamp(dd, 0.0, 1.0), 5.0);
		emit = room * lit * mix(room_day, room_night, lamp) * (1.0 - fres);
		emit += sky * glass_mirror * fres * (1.0 - 0.7 * lamp);
		base = vec3(0.02);
		rough = 0.05;
		metal = 0.0;
	} else if (code == 5) {
		// Lightbox face.
		emit = base * mix(glow_day, glow_night, lamp);
		rough = 0.3;
	} else if (code == 6) {
		// Canopy LED panel: a lens with dots, very bright.
		vec2 c = fract(UV * 22.0) - 0.5;
		float dot_ = 1.0 - smoothstep(0.25, 0.4, length(c));
		dot_ = mix(dot_, 0.5, smoothstep(0.2, 0.6, fwidth(UV.x) * 22.0));
		emit = vec3(1.0, 0.98, 0.94) * (0.7 + 0.3 * dot_) * mix(soffit_day, soffit_night, lamp);
		base = vec3(0.9);
		rough = 0.25;
	} else if (code == 7) {
		// LED price digit (UV 0..1 over the cell, UV2.x the digit).
		float on = rs_digit(UV, int(UV2.x + 0.5));
		float off = rs_digit(UV, 8) * 0.04;
		emit = base * (on + off) * mix(led_day, led_night, lamp);
		base = vec3(0.015);
		rough = 0.25;
		metal = 0.0;
	} else if (code == 8) {
		emit = base * mix(neon_day, neon_night, lamp);
		rough = 0.2;
	} else if (code == 9) {
		// Rubber: a tread of blocks across the face (UV.x round the tyre), worn shoulders.
		vec2 tr = vec2(UV.x * 14.0, UV.y * 6.0);
		float block = step(0.25, fract(tr.x)) * step(0.2, fract(tr.y + floor(tr.x) * 0.5));
		base = vec3(0.035, 0.035, 0.038) * (0.75 + 0.35 * block);
		rough = 0.85 - 0.1 * block;
		metal = 0.0;
	} else if (code == 10) {
		// A pump's screen: a dark LCD with a lit ad panel and a price total.
		vec2 c = fract(UV);
		float panel = step(0.08, c.x) * step(c.x, 0.92) * step(0.1, c.y) * step(c.y, 0.9);
		vec3 lcd = mix(vec3(0.15, 0.45, 0.85), vec3(0.95, 0.65, 0.15), step(0.55, c.y));
		lcd = mix(lcd, vec3(0.9), step(0.8, rs_noise(c * vec2(30.0, 8.0))) * 0.6);
		emit = lcd * panel * screen_glow * (0.6 + 0.6 * lamp);
		base = vec3(0.02);
		rough = 0.1;
	} else if (code == 11) {
		// Car wash cloth and foam: soft strips hanging in a curtain, wet.
		float strip = rs_noise(vec2(UV.x * 18.0, UV.y * 1.5));
		base *= 0.65 + 0.5 * strip;
		base = mix(base, vec3(0.9, 0.92, 0.95), smoothstep(0.75, 0.95, rs_noise(UV * vec2(9.0, 3.0))) * 0.5);
		rough = 0.45;
		metal = 0.0;
	} else if (code == 12) {
		rough = 0.08;
		metal = 1.0;
		base = max(base, vec3(0.55));
	} else if (code == 13) {
		// Dark plain glass: the sky by Fresnel, emitted.
		float dd = clamp(dot(V, -normalize(v_wnormal)), 0.0, 1.0);
		float fres = 0.05 + 0.95 * pow(1.0 - dd, 5.0);
		emit = sky * glass_mirror * fres * (1.0 - 0.6 * lamp);
		base = base * 0.15;
		rough = 0.06;
		metal = 0.0;
	} else if (code == 14) {
		// A drive-thru menu board: printed panels lit from behind.
		vec3 m = cs_srgb_to_linear(rs_menu(fract(UV), floor(UV.x) + UV2.x * 13.0));
		base = m;
		emit = m * mix(glow_day * 1.4, glow_night, lamp);
		rough = 0.25;
		metal = 0.0;
	} else if (code == 15) {
		// Marquee bulbs, chasing round (UV.x is the bulb's place along the run).
		float chase = step(0.5, fract(UV.x * 0.5 - TIME * 1.5));
		emit = base * mix(bulb_day, bulb_night * (0.55 + 0.45 * chase), lamp);
		rough = 0.15;
	} else if (code == 16) {
		// A painted wall sign: brush strokes and flaking, sun-faded.
		float flake = smoothstep(0.72, 0.8, rs_fbm(UV * 3.0 + 5.0));
		base = mix(base, vec3(0.85, 0.82, 0.76), flake * 0.55);
		base *= 0.9 + 0.12 * rs_noise(vec2(UV.x * 30.0, UV.y * 2.0));
		rough = 0.8;
	} else if (code == 17) {
		// A roll-up door: horizontal slats, a little dented and dirty at the foot.
		float slat = fract(UV.y / 0.075);
		float groove = smoothstep(0.0, 0.12, slat) * smoothstep(1.0, 0.86, slat);
		base *= 0.78 + 0.25 * groove;
		base *= 1.0 - 0.25 * smoothstep(0.9, 0.0, UV.y) * rs_noise(UV * 4.0);
		metal = 0.5;
		rough = 0.45;
	} else if (code == 19) {
		// Stacked-stone veneer (the coffee shop's walls and pylon): courses of rough flat stones in
		// three tones, dark mortar between, faded to its mean under a pixel.
		vec2 q = vec2(dot(v_world.xz, vec2(0.7071, 0.7071)) + UV.x * 0.0, v_world.y);
		vec2 cs = vec2(0.42, 0.11);
		float row = floor(q.y / cs.y);
		vec2 g = vec2(q.x / cs.x + rs_hash(vec2(row, 1.0)) * 3.0, q.y / cs.y);
		vec2 id = floor(g);
		vec2 f = fract(g);
		float mortar = smoothstep(0.0, 0.07, f.x) * smoothstep(1.0, 0.93, f.x) * smoothstep(0.0, 0.12, f.y) * smoothstep(1.0, 0.88, f.y);
		float tone = rs_hash(id);
		vec3 st = mix(base * 0.75, base * 1.2, tone) * (0.85 + 0.25 * rs_noise(q * 23.0));
		float fade = smoothstep(0.02, 0.1, fwidth(q.y));
		base = mix(mix(base * 0.45, st, mortar), base * 0.92, fade);
		rough = 0.85;
	} else if (code == 18) {
		// Donut glaze with sprinkles (the giant donut).
		vec2 sp = UV * vec2(9.0, 4.0);
		vec2 id = floor(sp);
		vec2 f = fract(sp) - 0.5;
		float hs = rs_hash(id);
		float ang = hs * 6.2831;
		vec2 r = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * f;
		float spr = (1.0 - smoothstep(0.07, 0.1, abs(r.y))) * (1.0 - smoothstep(0.24, 0.28, abs(r.x))) * step(0.35, hs);
		vec3 sc = 0.55 + 0.45 * cos(6.2831 * (rs_hash(id + 3.0) + vec3(0.0, 0.33, 0.67)));
		base = mix(base, sc, spr);
		rough = 0.28;
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
}
