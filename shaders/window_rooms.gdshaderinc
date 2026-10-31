// The traced rooms of the window-interiors pass (window_interiors.gdshaderinc has the rolls):
// building.gdshader only, near walls. Included after room_interior() and hash21().
// Wall space as room_interior(): x along the wall, y up, z into the building; the window opening
// is x 0..wide, y 0..high at z 0. Shader includes use // comments.

// Ray against an axis-aligned box: the entry distance, or 1e9 for a miss. `n` the face's axis
// (0 x, 1 y, 2 z) it entered by.
float wr_box(vec3 ro, vec3 rd, vec3 b0, vec3 b1, out int n) {
	vec3 inv = 1.0 / vec3(abs(rd.x) > 1e-5 ? rd.x : 1e-5, abs(rd.y) > 1e-5 ? rd.y : 1e-5, abs(rd.z) > 1e-5 ? rd.z : 1e-5);
	vec3 t0 = (b0 - ro) * inv;
	vec3 t1 = (b1 - ro) * inv;
	vec3 lo = min(t0, t1);
	vec3 hi = max(t0, t1);
	float tn = max(max(lo.x, lo.y), lo.z);
	float tf = min(min(hi.x, hi.y), hi.z);
	n = lo.x >= lo.y && lo.x >= lo.z ? 0 : (lo.y >= lo.z ? 1 : 2);
	return (tn > 0.0 && tn < tf) ? tn : 1e9;
}

// A standing or seated person as a vertical capsule (body) and a sphere (head): the entry
// distance or 1e9, and whether it was the head.
float wr_person(vec3 ro, vec3 rd, vec2 at, float y0, float y1, float r, float head_r, out bool head) {
	head = false;
	float best = 1e9;
	// The body: a vertical cylinder at `at` (x, z), y0..y1.
	vec2 o = ro.xz - at;
	vec2 d = rd.xz;
	float a = dot(d, d);
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float disc = b * b - a * c;
	if (a > 1e-8 && disc > 0.0) {
		float t = (-b - sqrt(disc)) / a;
		float y = ro.y + rd.y * t;
		if (t > 0.0 && y > y0 && y < y1) {
			best = t;
		}
	}
	// The head.
	vec3 hc = vec3(at.x, y1 + head_r * 1.25, at.y);
	vec3 oc = ro - hc;
	float hb = dot(oc, rd);
	float hd = hb * hb - (dot(oc, oc) - head_r * head_r);
	if (hd > 0.0) {
		float t = -hb - sqrt(hd);
		if (t > 0.0 && t < best) {
			best = t;
			head = true;
		}
	}
	return best;
}

// A flat in the evening, behind the glass: a room wider than the window (the walls stand
// `side` metres beyond its jambs), its floor below the sill, a sofa along the back wall with a
// picture over it, a shelf on one side, a floor or table lamp whose light falls off from where it
// stands (its shade glowing), now and then somebody walking across in front of the sofa; then
// whatever hangs at the glass. `t` the clock (TIME), `wind` the draught for an open window.
// `lamp` comes back as how strongly the lamp lights the point (room_interior's contract), `glow`
// what glows by itself (the shade), `open_k` 1 where the lower sash stands open (no glass there).
vec3 home_room(vec2 w, vec3 dir, float wide, float high, float deep_in, uint key, float t, float wind, float night,
		out float depth_t, out float lamp, out vec3 glow, out float open_k) {
	vec3 rd = normalize(dir);
	vec3 ro = vec3(w.x * wide, w.y * high, 0.0);
	float r1 = float(wl_hash(key, 110u) % 1000u) / 1000.0;
	float r2 = float(wl_hash(key, 111u) % 1000u) / 1000.0;
	float r3 = float(wl_hash(key, 112u) % 1000u) / 1000.0;
	float side = 0.5 + 0.9 * r1;
	float deep = clamp(deep_in * (0.9 + 0.6 * r2), 2.8, 5.2);
	float floor_y = -0.85;
	float ceil_y = high + 0.30;
	vec3 lo = vec3(-side, floor_y, 0.0);
	vec3 hi = vec3(wide + side, ceil_y, deep);
	glow = vec3(0.0);
	open_k = 0.0;

	// The shell: the far side of the room's box.
	float best = 1e9;
	int surf = 0; // 0 back, 1 side, 2 floor, 3 ceiling, 4 sofa, 5 shelf, 6 person, 7 head
	if (rd.z > 1e-4) { float tt = (hi.z - ro.z) / rd.z; if (tt < best) { best = tt; surf = 0; } }
	if (abs(rd.x) > 1e-4) { float tt = ((rd.x > 0.0 ? hi.x : lo.x) - ro.x) / rd.x; if (tt > 0.0 && tt < best) { best = tt; surf = 1; } }
	if (abs(rd.y) > 1e-4) { float tt = ((rd.y > 0.0 ? hi.y : lo.y) - ro.y) / rd.y; if (tt > 0.0 && tt < best) { best = tt; surf = rd.y > 0.0 ? 3 : 2; } }
	best = min(best, 1e8);

	// The sofa along the back wall, the shelf on one side.
	int fn = 2;
	float sx0 = mix(-side * 0.5, wide * 0.25, r3);
	float sx1 = min(sx0 + 2.1, hi.x - 0.1);
	float ts = wr_box(ro, rd, vec3(sx0, floor_y, deep - 0.9), vec3(sx1, floor_y + 0.82, deep), fn);
	if (ts < best) { best = ts; surf = 4; }
	bool shelf_right = r2 > 0.5;
	float shx = shelf_right ? hi.x - 0.38 : lo.x;
	int fn2 = 0;
	float tsh = wr_box(ro, rd, vec3(shx, floor_y, 0.9), vec3(shx + 0.38, floor_y + 1.95, 0.9 + 1.2 + 0.8 * r1), fn2);
	if (r1 > 0.35 && tsh < best) { best = tsh; surf = 5; fn = fn2; }

	// Somebody walking across, now and then: a few seconds every 10-30 s, alternate ways.
	float period = 10.0 + 20.0 * r3;
	float phase = (t + 97.0 * r1) / period;
	float s = fract(phase) * period / 3.2;
	bool walking = wi_walker(key) && s < 1.0;
	bool head = false;
	vec3 pc = vec3(0.0);
	if (walking) {
		float dir_k = mod(floor(phase), 2.0) < 0.5 ? s : 1.0 - s;
		float px = mix(lo.x - 0.3, hi.x + 0.3, dir_k);
		float pz = deep - 1.45;
		float bob = 0.025 * abs(sin(s * 14.0));
		float tp = wr_person(ro, rd, vec2(px, pz), floor_y, floor_y + 1.45 + bob, 0.19, 0.115, head);
		if (tp < best) { best = tp; surf = head ? 7 : 6; pc = vec3(px, floor_y + 1.0, pz); }
	}

	vec3 hit = ro + rd * best;
	depth_t = clamp(best / max(deep, 0.01), 0.0, 2.0);

	// Paint and materials, LINEAR.
	vec3 paint = mix(vec3(0.74, 0.70, 0.62), vec3(0.62, 0.66, 0.66), r2);
	paint = mix(paint, vec3(0.70, 0.56, 0.44), step(0.78, r3));
	vec3 col = paint;
	if (surf == 0) {
		// A picture over the sofa (its frame and a dark-ish canvas).
		vec2 pp = vec2(hit.x - (sx0 + sx1) * 0.5, hit.y - (floor_y + 1.55));
		vec2 ph = vec2(0.45 + 0.25 * r1, 0.32);
		if (abs(pp.x) < ph.x && abs(pp.y) < ph.y) {
			col = (abs(pp.x) > ph.x - 0.04 || abs(pp.y) > ph.y - 0.04) ? vec3(0.12, 0.10, 0.08) : mix(vec3(0.25, 0.32, 0.40), vec3(0.55, 0.38, 0.22), r1);
		}
		col *= 0.9;
	} else if (surf == 1) {
		col *= 0.78;
	} else if (surf == 2) {
		col = mix(vec3(0.30, 0.20, 0.12), vec3(0.42, 0.38, 0.33), r1);
		// A rug in the middle.
		if (abs(hit.x - wide * 0.5) < 1.1 && abs(hit.z - deep * 0.55) < 0.8) {
			col = mix(vec3(0.42, 0.18, 0.14), vec3(0.20, 0.26, 0.32), r3);
		}
	} else if (surf == 3) {
		col *= 1.08;
	} else if (surf == 4) {
		col = mix(vec3(0.20, 0.22, 0.26), vec3(0.45, 0.36, 0.26), r2) * (fn == 1 ? 1.15 : 0.85);
	} else if (surf == 5) {
		// Shelves with books: bands of colour.
		float band = fract((hit.y - floor_y) / 0.38);
		col = band < 0.08 ? vec3(0.30, 0.22, 0.14) : mix(vec3(0.18, 0.14, 0.12), vec3(0.45, 0.30, 0.20), fract(sin(floor(hit.z * 9.0) * 12.9898) * 437.585));
	} else if (surf == 6) {
		col = mix(vec3(0.10, 0.11, 0.14), vec3(0.32, 0.18, 0.14), r2);
	} else {
		col = mix(vec3(0.45, 0.30, 0.22), vec3(0.20, 0.14, 0.10), r1);
	}

	// The lamp: a floor lamp by the sofa's end, or a table lamp on the shelf.
	vec3 lp = vec3(r1 > 0.5 ? sx1 + 0.3 : sx0 - 0.3, floor_y + (r2 > 0.6 ? 1.05 : 1.45), deep - 0.55);
	vec3 dl = hit - lp;
	float fall = 1.0 / (1.0 + dot(dl, dl) * 0.45);
	lamp = 0.22 + 1.6 * fall;
	if (surf == 3) {
		// The shade throws a pool on the ceiling.
		lamp += 1.2 * exp(-dot(dl.xz, dl.xz) * 1.2);
	}
	if (surf == 6 || surf == 7) {
		lamp *= 0.55;
	}
	// The shade itself, glowing, where the ray passes it before what it hits.
	vec3 oc = lp - ro;
	float along = clamp(dot(oc, rd), 0.0, best);
	// A drum shade, 22 cm tall, wider at the foot: where the ray passes it, how far up the shade.
	vec3 pa = ro + rd * along - lp;
	float up_k = clamp((pa.y + 0.12) / 0.22, 0.0, 1.0);
	float rad = mix(0.17, 0.12, up_k);
	float inside_s = (1.0 - smoothstep(rad * 0.85, rad, length(pa.xz))) * step(-0.12, pa.y) * step(pa.y, 0.10);
	float shade = inside_s * step(along, best - 0.01);
	glow = vec3(1.0, 0.92, 0.80) * shade * mix(0.9, 0.5, up_k);
	// Light falls off with depth as room_interior's does, more gently (the lamp is in the room).
	col *= mix(1.0, 0.6, clamp(depth_t, 0.0, 1.0));

	// What hangs at the glass.
	int cover = wi_cover(key);
	float d = wi_draw(key);
	vec3 fab = wi_fabric(key);
	bool open_w = wi_open(key) && night < 0.5;
	float sway = open_w ? (0.6 + 0.6 * clamp(wind, 0.0, 1.5)) : 0.0;
	float px = w.x * wide;
	if (cover == 0) {
		// Drapes, lined: two panels, gathered in folds, drawn to `d`; in an open window the hem
		// swings out and the folds travel with the draught.
		float a = (0.10 + 0.40 * d) * wide;
		float billow = sway * (0.05 + 0.12 * (1.0 - w.y)) * sin(t * 1.4 + w.y * 2.6 + r1 * 6.0);
		float left = a + billow;
		float right = wide - a + billow * 0.7;
		if (px < left || px > right) {
			float fold = 0.72 + 0.28 * cos(px * 44.0 + billow * 30.0);
			col = fab * fold;
			depth_t = 0.0;
			lamp = 0.45;
			glow = vec3(0.0);
		}
	} else if (cover == 1) {
		// Sheers across the whole pane, the room softened behind them; they glow lit from behind.
		float billow = sway * 0.08 * sin(t * 1.7 + w.y * 3.1 + r2 * 5.0) * (1.0 - w.y);
		float fold = 0.8 + 0.2 * cos((px + billow) * 38.0);
		vec3 sh = mix(fab, vec3(0.92, 0.91, 0.88), 0.55) * fold;
		float k = 0.62 + 0.2 * (1.0 - w.y) * sway;
		col = mix(col, sh, k);
		lamp = mix(lamp, 0.85 + 0.6 * fall, k);
		depth_t = mix(depth_t, 0.0, k);
		glow *= 1.0 - k * 0.7;
	} else if (cover == 2) {
		// A roller blind down to `d`, its hem bar.
		float level = 1.0 - d;
		if (w.y > level) {
			col = fab * (w.y < level + 0.03 ? 0.55 : 0.95);
			depth_t = 0.0;
			lamp = 0.9;
			glow = vec3(0.0);
		}
	} else if (cover == 3) {
		float level = 1.0 - d;
		if (w.y > level) {
			col = vec3(0.82, 0.80, 0.75) * (0.86 + 0.14 * step(0.5, fract((w.y - level) * high * 40.0)));
			depth_t = 0.0;
			lamp = 1.0;
			glow = vec3(0.0);
		}
	} else if (cover == 4) {
		// Vertical blinds, turned part-way: louvres with the room in the gaps.
		float v = fract(px / 0.09);
		if (v < 0.68) {
			col = vec3(0.80, 0.79, 0.76) * (0.82 + 0.25 * v);
			depth_t = 0.0;
			lamp = 0.95;
			glow = vec3(0.0);
		}
	}
	// Fabric at the glass catches the daylight a room's depth never does: brighter as paint, and
	// lit by the lamp a little less (lamp is a multiplier on the same colour after dark).
	if (depth_t < 0.001) {
		col *= 1.9;
		lamp /= 1.9;
	}
	if (open_w) {
		// The lower sash pushed up behind the upper one: no glass in the bottom half.
		open_k = 1.0 - step(0.5, w.y);
		// The upper sash's meeting rail across the middle, in front of everything.
		if (abs(w.y - 0.5) * high < 0.035) {
			col = vec3(0.80, 0.79, 0.76);
			depth_t = 0.0;
			lamp = 0.4;
			glow = vec3(0.0);
			open_k = 0.0;
		}
	}
	return col;
}

// Somebody at the desk of an office room_interior() traced (its desk, rolled the same way),
// sitting with their back to the window, the monitor in front of them glowing toward us.
// `best_in` is how far the room's own trace reached (depth_t x deep); `present` whether anybody
// is in. Overrides col / depth_t / lamp where the person or the screen is nearer, and returns the
// screen's light in `glow`.
vec3 office_people(vec2 w, vec3 dir, float wide, float high, float deep, float room_seed, bool present, vec3 col_in,
		inout float depth_t, inout float lamp, out vec3 glow) {
	glow = vec3(0.0);
	vec3 col = col_in;
	if (!present || hash21(vec2(room_seed, 41.7)) <= 0.5 || dir.z <= 1e-4) {
		return col;
	}
	vec3 rd = normalize(dir);
	vec3 ro = vec3(w.x * wide, w.y * high, 0.0);
	float best = depth_t * deep;
	float z0 = deep * mix(0.35, 0.6, hash21(vec2(room_seed, 43.1)));
	float top = high * mix(0.30, 0.42, hash21(vec2(room_seed, 44.9)));
	// One or two workers along the desk.
	float n = hash21(vec2(room_seed, 51.3)) > 0.6 ? 2.0 : 1.0;
	for (float i = 0.0; i < 2.0; i += 1.0) {
		if (i >= n) break;
		float xk = (i + 0.3 + 0.4 * hash21(vec2(room_seed, 52.7 + i))) / n;
		float x = xk * wide;
		// The screen: a panel on the desk, its face toward the window.
		float sz = z0 + 0.12;
		float ts = (sz - ro.z) / rd.z;
		vec3 q = ro + rd * ts;
		if (ts > 0.0 && ts < best && abs(q.x - x) < 0.30 && q.y > top + 0.06 && q.y < top + 0.42) {
			bool bezel = abs(q.x - x) > 0.27 || q.y < top + 0.09 || q.y > top + 0.39;
			col = bezel ? vec3(0.04) : vec3(0.08, 0.09, 0.11);
			glow = bezel ? vec3(0.0) : mix(vec3(0.55, 0.70, 1.0), vec3(0.95, 0.95, 0.90), hash21(vec2(room_seed, 53.9 + i)));
			lamp = 0.2;
			best = ts;
			depth_t = clamp(ts / max(deep, 0.01), 0.0, 2.0);
		}
		// Their chair's back, between them and the window.
		int cn = 2;
		float tc = wr_box(ro, rd, vec3(x - 0.21, top - 0.30, z0 - 0.86), vec3(x + 0.27, top + 0.16, z0 - 0.80), cn);
		if (tc < best) {
			col = vec3(0.05, 0.05, 0.06);
			lamp = 0.3;
			glow = vec3(0.0);
			best = tc;
			depth_t = clamp(tc / max(deep, 0.01), 0.0, 2.0);
		}
		// The worker, seated a little nearer the window than the screen: shoulders and head over
		// the chair, the rest hidden by it and the desk.
		bool head = false;
		float tp = wr_person(ro, rd, vec2(x + 0.05, z0 - 0.55), top - 0.25, top + 0.36, 0.20, 0.105, head);
		if (tp < best) {
			col = head ? vec3(0.10, 0.07, 0.05) : mix(vec3(0.10, 0.11, 0.14), vec3(0.42, 0.40, 0.38), hash21(vec2(room_seed, 54.1 + i)));
			lamp = 0.5;
			glow = vec3(0.0);
			best = tp;
			depth_t = clamp(tp / max(deep, 0.01), 0.0, 2.0);
		}
	}
	return col;
}
