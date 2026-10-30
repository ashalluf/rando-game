// The street level up close (fleet wave 3, "facades-street"): what a generated Building's first
// two storeys look like from the pavement at 2-20 m. Included by building.gdshader (near walls
// only - the far boxes never get close enough to need any of it), all of it off unless
// `facade_street` (Building sets it from FacadeStreet.enabled; FACADES_STREET=0 is the A/B).
//
// - Relief on the wall's own UVs (u along the wall, v up it, metres): stucco's sand-float grain and
//   trowel lumps (or a skip-trowel finish by hash), precast concrete's form-tie holes and bug holes,
//   the stone base course's V-joints, brick mortar raked back in its texture. It is a HEIGHT FIELD
//   in metres sampled three times (fs_height()) and handed to the renderer as a tilt of NORMAL,
//   faded out by distance and by the pixel's footprint (a grain under a pixel only aliases).
// - Repairs and failure: render patched in mismatched paint, hairline cracks running off the
//   window corners on stucco and precast.
// - Where the wall meets the pavement: the splash-back and rising damp with a tide line and salt
//   bloom, the contact shade along the foot, kick scuffs, hand grime and chipped arrises at the
//   corners - on the wall, the bulkhead and the shop piers alike.
// - A door on a ground floor that has no shops (fs_door_col(): an integer roll the props side,
//   FacadeStreet.door_col(), makes bit for bit, so the lamp and the step stand at it), drawn with
//   its frame, leaf, panels or wired glass, kick plate, lever, deadbolt, mail slot, and the wall
//   lamp over it washing the wall after dark.
// - After dark, the gooseneck lamps FacadeStreet hangs over a share of the sign boards
//   (shop_byte salt 46) wash their board.
// Salts: wl_hash 90-99 on fs_face_key(), shop_byte 46-47 on the shop key. Shader includes use //
// comments.

uniform bool facade_street = false;
// The face that backs onto a service alley (Building.back_face): AlleyKit dresses it, no door here.
uniform int street_back_face = 0;
// World Y of the building's foot (its position): a part standing here stands on the pavement.
uniform float street_ground_y = 0.0;
// Relief is full to `street_relief_near` metres and gone by `street_relief_far`.
uniform float street_relief_near = 14.0;
uniform float street_relief_far = 55.0;
// How strong the relief is (1 = as authored).
uniform float street_relief = 1.0;
// The grime at the foot of the wall fades out by here (its fine marks alias further out).
uniform float street_grime_far = 160.0;
// Doors hand over to the window grid between these distances, so the far boxes (which draw the
// window) meet the same wall.
uniform float street_door_far = 150.0;


float fs_vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


// The integer key of one wall of one part: the building's shader seed, the face (1..4) and the
// wall's length in quarter metres (two parts of a building rarely share a face length).
// FacadeStreet.face_key() is the same.
uint fs_face_key(float b_seed, float face, float face_len) {
	uint sd = uint(clamp(abs(b_seed), 0.0, 999.0) + 0.5);
	uint f = uint(clamp(face, 0.0, 7.0) + 0.5);
	uint l = uint(floor(face_len * 4.0 + 0.5)) & 4095u;
	return (sd * 8u + f) * 4096u + l;
}


// The bay (shader `col`, counted along u) a ground floor without shops has its door in, or -1:
// 63 % of walls of three bays or more, never an end bay. FacadeStreet.door_col() is this.
int fs_door_col(uint key, float cols) {
	if (cols < 2.5) {
		return -1;
	}
	if ((wl_hash(key, 90u) >> 24u) >= 160u) {
		return -1;
	}
	return 1 + int(wl_hash(key, 91u) % uint(cols - 2.0 + 0.5));
}


// The door's width and height (metres) in a bay of `pitch` and a storey of `fl`.
vec2 fs_door_size(float pitch, float fl) {
	return vec2(clamp(pitch * 0.55, 0.92, 1.05), min(2.22, fl - 0.62));
}


// The wall's height at `p` (metres along, up), metres out of the face (negative is in).
// kind: 0 stucco, 1 skip-trowel stucco, 2 precast concrete, 3 the stone base course, 4 smooth
// render. `g` fades the fine octaves (1 resolved .. 0 under a pixel).
float fs_height(vec2 p, int kind, float b_seed, vec2 g) {
	float h = 0.0;
	if (kind <= 1 || kind == 4) {
		// Sand float: ~5 mm grains, then trowel lumps at 8 cm and the hand's sweep at 40 cm.
		float grain = (kind == 4 ? 0.35 : 1.0) * 0.0007 * (fs_vn(p * 190.0 + b_seed) - 0.5);
		float lump = 0.0026 * (fs_vn(p * 11.0 + b_seed * 0.37) - 0.5);
		float sweep = 0.0045 * (fs_vn(vec2(p.x * 2.1 + p.y * 1.3, p.y * 2.6) + b_seed * 0.11) - 0.5);
		h = grain * g.x + lump * g.y + sweep;
		if (kind == 1) {
			// Skip trowel: flat dabs of plaster laid over the scratch coat, their edges rounded.
			float dab = smoothstep(0.52, 0.62, fs_vn(p * vec2(3.6, 4.8) + b_seed * 0.71));
			h += 0.0035 * dab * g.y;
		}
	} else if (kind == 2) {
		// Precast: form-tie holes on a 60 cm grid set off the panel joints, sealed with a darker
		// plug, and bug holes - the air pockets against the form face.
		vec2 c = fract(p / 0.6 + 0.5) - 0.5;
		float d = length(c) * 0.6;
		h -= 0.007 * (1.0 - smoothstep(0.009, 0.014, d)) * g.y;
		vec2 bc = floor(p / 0.035);
		float bug = step(hash21(bc + b_seed), 0.07);
		float bd = length(fract(p / 0.035) - 0.5) * 0.035;
		h -= 0.002 * bug * (1.0 - smoothstep(0.0015, 0.004, bd)) * g.x;
		h += 0.0008 * (fs_vn(p * 40.0 + b_seed) - 0.5) * g.x;
	} else if (kind == 3) {
		// Ashlar: 92 cm courses, blocks 1.84 m long half-bonded (the base course's own layout),
		// V-jointed, each face very slightly pillowed.
		// Centred on the base course's own joints (building.gdshader: the bottom 5 % of a course,
		// the first 1.8 % of a block).
		float course = p.y / 0.92 - 0.025;
		float cy = fract(course);
		float bx = fract((p.x + floor(p.y / 0.92) * 0.46) / 1.84 - 0.009);
		float jd = min(min(cy, 1.0 - cy) * 0.92, min(bx, 1.0 - bx) * 1.84);
		h -= 0.014 * (1.0 - smoothstep(0.004, 0.026, jd));
		h += 0.003 * smoothstep(0.0, 0.25, jd);
		h += 0.0012 * (fs_vn(p * 23.0 + b_seed) - 0.5) * g.y;
	}
	return h;
}


// The tilt the relief gives the normal: d(height)/d(along), d(height)/d(up).
vec2 fs_slope(vec2 p, int kind, float b_seed, vec2 g, float px) {
	float e = max(0.0015, px * 0.6);
	float h0 = fs_height(p, kind, b_seed, g);
	float hu = fs_height(p + vec2(e, 0.0), kind, b_seed, g);
	float hv = fs_height(p + vec2(0.0, e), kind, b_seed, g);
	return vec2(hu - h0, hv - h0) / e;
}


// A patch of render repaired and painted in a near match: (inside 0..1, its edge, tone, cell seed).
// On a 1.9 x 1.4 m grid, 16 % of cells, set back from the cell's sides by a hash.
vec4 fs_patch(vec2 p, float face, float b_seed) {
	vec2 cell = floor(p / vec2(1.9, 1.4));
	float r = hash21(cell + vec2(face * 17.0, b_seed));
	if (r > 0.16) {
		return vec4(0.0);
	}
	vec2 lo = cell * vec2(1.9, 1.4) + vec2(hash21(cell + 3.1), hash21(cell + 7.7)) * vec2(0.7, 0.5);
	vec2 hi = lo + vec2(0.5 + 0.7 * hash21(cell + 1.3), 0.35 + 0.5 * hash21(cell + 5.9));
	// A ragged outline: the new render feathered out over the old.
	float wob = 0.03 * (fs_vn(p * 9.0 + cell) - 0.5);
	vec2 d = min(p - lo, hi - p) + wob;
	float inside = smoothstep(0.0, 0.012, min(d.x, d.y));
	float edge = (1.0 - smoothstep(0.0, 0.02, abs(min(d.x, d.y))));
	return vec4(inside, edge, 0.90 + 0.18 * hash21(cell + 11.0), r);
}


// A hairline crack off the nearest corner of the window in this cell (cell metres `q`, the
// opening's centre `c` and half size `h`): the classic diagonal running from a stucco or precast
// opening's corner. A third of corners have one, 25-95 cm long. Returns its darkness 0..1.
float fs_crack(vec2 q, vec2 c, vec2 h, float key, float px) {
	vec2 s = vec2(q.x < c.x ? -1.0 : 1.0, q.y < c.y ? -1.0 : 1.0);
	vec2 corner = c + s * h;
	float k = key + (s.x + 1.0) * 0.5 + (s.y + 1.0);
	float roll = hash21(vec2(k, 3.7));
	if (roll > 0.34) {
		return 0.0;
	}
	float ang = (hash21(vec2(k, 9.1)) - 0.5) * 0.7;
	vec2 dir = normalize(vec2(s.x, s.y * 1.25));
	dir = vec2(dir.x * cos(ang) - dir.y * sin(ang), dir.x * sin(ang) + dir.y * cos(ang));
	vec2 r = q - corner;
	float t = dot(r, dir);
	float len = 0.25 + 0.7 * hash21(vec2(k, 1.9));
	if (t < 0.0 || t > len) {
		return 0.0;
	}
	float side = dot(r, vec2(-dir.y, dir.x));
	side -= 0.012 * sin(t * 31.0 + k * 5.0) + 0.005 * sin(t * 87.0 + k);
	float w = max(px * 0.7, 0.0012);
	float line = 1.0 - smoothstep(0.0, w, abs(side));
	// A line finer than the pixel keeps its share of it, no more.
	return line * min(1.0, 0.0018 / max(px, 1e-4)) * (1.0 - t / len);
}


// The foot of the wall: splash-back and rising damp with a tide line and salt bloom, the contact
// shade along the pavement, scuffs, and grime and chips round the corners at hand height.
// `up` metres over the part's foot, `u` along the wall, `face_len` the wall's length, `porous`
// 1 for masonry and render (salt shows), `fade` 1 near .. 0 at street_grime_far.
void fs_plinth(inout vec3 albedo, inout float rough, float up, float u, float face_len, float face,
		float b_seed, float porous, float fade, float px) {
	if (up > 2.2 || fade <= 0.0) {
		return;
	}
	float fine = 1.0 - smoothstep(0.01, 0.04, px);
	// The damp line: ragged, 15-55 cm up, higher where water stands.
	float hs = 0.16 + 0.26 * fs_vn(vec2(u * 0.55, face * 3.0 + b_seed)) + 0.07 * fs_vn(vec2(u * 3.3, face + b_seed));
	float damp = 1.0 - smoothstep(hs - 0.06, hs + 0.01, up);
	vec3 grey = vec3(dot(albedo, vec3(0.3, 0.55, 0.15)));
	albedo = mix(albedo, mix(albedo, grey, 0.35) * 0.62, damp * 0.75 * fade);
	rough = mix(rough, min(rough, 0.78), damp * fade);
	// The tide line, and salt bloomed out of the damp band on porous walls.
	float tide = exp(-pow((up - hs) / 0.014, 2.0)) * fine;
	float bloom = smoothstep(0.58, 0.78, fs_vn(vec2(u * 4.0, up * 6.0) + b_seed * 0.3)) * damp * fine;
	vec3 salt = vec3(0.74, 0.73, 0.69);
	albedo = mix(albedo, salt, (0.22 * tide + 0.3 * bloom) * porous * fade);
	// Where the wall meets the pavement: the shade in the corner and the dirt splashed up it.
	float foot = 1.0 - smoothstep(0.0, 0.22, up);
	albedo *= 1.0 - 0.42 * foot * fade;
	// Scuffs: shoes, bins and trolleys, dark streaks under knee height.
	vec2 sc = vec2(u * 3.0, up * 9.0);
	float scuff = step(hash21(floor(sc) + vec2(face, b_seed)), 0.09) * (1.0 - smoothstep(0.08, 0.48, up))
		* smoothstep(0.0, 0.5, 1.0 - abs(fract(sc.y) - 0.5) * 2.0);
	albedo *= 1.0 - 0.3 * scuff * fine * fade;
	// The corners: hands and shoulders at 0.6-1.9 m, and chips knocked off the arris.
	float cd = min(u, face_len - u);
	float hand = (1.0 - smoothstep(0.05, 0.45, cd)) * smoothstep(0.5, 0.8, up) * (1.0 - smoothstep(1.6, 2.0, up));
	hand *= 0.5 + 0.5 * fs_vn(vec2(u * 7.0, up * 5.0) + b_seed);
	albedo *= 1.0 - 0.2 * hand * fade;
	float chip = step(hash21(floor(vec2(cd * 25.0, up * 7.0)) + b_seed + face), 0.12) * (1.0 - smoothstep(0.02, 0.05, cd));
	albedo = mix(albedo, albedo * 1.35 + vec3(0.06), chip * fine * fade * porous);
}


// One door, drawn in the door's own frame: `q` metres from the middle of its bay (x) and up from
// the part's foot (y); `ds` its width and height. Writes the door over the wall and returns true
// inside the door and its frame. `slope` takes the tilt of the panels' mouldings.
bool fs_door(vec2 q, vec2 ds, uint key, float px, float day, inout vec3 albedo, inout float rough,
		inout float metal, inout vec2 slope) {
	float fw = 0.065;
	vec2 half_o = vec2(ds.x * 0.5 + fw, ds.y + fw);
	if (abs(q.x) > half_o.x || q.y > half_o.y) {
		return false;
	}
	uint style = wl_hash(key, 92u) % 4u;
	uint paint_k = wl_hash(key, 94u) % 6u;
	vec3 paints[6] = vec3[6](vec3(0.05, 0.12, 0.08), vec3(0.025, 0.025, 0.028), vec3(0.32, 0.06, 0.04),
		vec3(0.30, 0.31, 0.30), vec3(0.06, 0.09, 0.18), vec3(0.62, 0.60, 0.55));
	vec3 paint = paints[paint_k];
	// The frame: pressed steel, painted to match or white.
	if (abs(q.x) > ds.x * 0.5 || q.y > ds.y) {
		albedo = (wl_hash(key, 95u) & 1u) == 0u ? paint * 1.2 : vec3(0.72, 0.71, 0.68);
		rough = 0.5;
		metal = 0.2;
		// The return into the opening, shaded on its inner edge.
		float inner = min(abs(abs(q.x) - ds.x * 0.5), abs(q.y - ds.y));
		albedo *= mix(0.6, 1.0, smoothstep(0.0, 0.03, inner));
		return true;
	}
	// The leaf, set back in the frame: its top edge and sides in the frame's shadow by day.
	vec2 l = vec2(q.x + ds.x * 0.5, q.y);
	float hinge_side = (wl_hash(key, 96u) & 1u) == 0u ? 1.0 : -1.0;
	float handle_x = hinge_side * (ds.x * 0.5 - 0.085);
	vec3 col = paint;
	rough = 0.42;
	metal = 0.08;
	if (style == 1u) {
		// Timber, six raised panels: stiles 11 cm, rails at the lock and the head, stained.
		col = vec3(0.20, 0.11, 0.055) * (0.85 + 0.3 * fs_vn(vec2(q.x * 40.0, q.y * 2.5)));
		rough = 0.6;
		metal = 0.0;
		float st = 0.11;
		float in_x = ds.x * 0.5 - st - abs(q.x);
		float split = abs(q.x) - 0.04;
		float rows3 = q.y < 0.95 ? (q.y - 0.18) / 0.77 : (q.y < 1.12 ? -1.0 : (q.y - 1.12) / (ds.y - 0.14 - 1.12));
		if (in_x > 0.0 && split > 0.0 && rows3 > 0.0 && rows3 < 1.0) {
			// The raised field's bevel: it catches the light on top and the left, shades below.
			float ex = min(in_x, split);
			float ey = min(rows3, 1.0 - rows3) * 0.6;
			float bev = 1.0 - smoothstep(0.0, 0.025, min(ex, ey));
			float out_x = in_x < split ? sign(q.x) : -sign(q.x);
			vec2 out_dir = ex < ey ? vec2(out_x, 0.0) : vec2(0.0, rows3 < 0.5 ? -1.0 : 1.0);
			// The field falls away toward its edge: height drops outward.
			slope -= out_dir * 0.8 * bev;
			col *= mix(1.0, 0.86, bev);
		}
	} else if (style == 2u) {
		// Steel with a wired-glass vision light: the dark glass, the wire grid, the bead round it.
		vec2 g = vec2(abs(q.x), q.y - 1.55);
		if (g.x < ds.x * 0.5 - 0.17 && abs(g.y) < 0.42) {
			vec3 glass_c = vec3(0.05, 0.06, 0.065);
			float wire = 1.0 - smoothstep(0.0, max(px, 0.0015), min(abs(fract(q.x / 0.025) - 0.5), abs(fract(q.y / 0.025) - 0.5)) * 0.025);
			wire *= min(1.0, 0.002 / max(px, 1e-4));
			col = mix(glass_c, vec3(0.35), wire * 0.6);
			rough = 0.08;
			metal = 0.1;
		} else if (g.x < ds.x * 0.5 - 0.14 && abs(g.y) < 0.45) {
			col = paint * 0.7;
		}
	} else if (style == 3u) {
		// A steel security screen door over the leaf: a frame and a perforated sheet.
		float sf = min(ds.x * 0.5 - abs(q.x), min(q.y, ds.y - q.y));
		if (sf < 0.05) {
			col = vec3(0.03);
			metal = 0.3;
		} else {
			vec2 hc = fract(q / 0.012) - 0.5;
			float hole = 1.0 - smoothstep(0.30, 0.38, length(hc));
			hole = mix(hole, 0.28, smoothstep(0.003, 0.009, px));
			col = mix(vec3(0.035), paint * 0.5, hole * 0.6);
			metal = 0.35;
			rough = 0.5;
		}
	} else {
		// Flush steel: two pressed lines, a little dented and rust-spotted at the foot.
		float line = 1.0 - smoothstep(0.0, max(px, 0.002), abs(abs(q.x) - (ds.x * 0.5 - 0.1)));
		col *= 1.0 - 0.25 * line;
		col *= 0.92 + 0.12 * fs_vn(q * 6.0);
		float rust = smoothstep(0.62, 0.8, fs_vn(q * vec2(14.0, 9.0))) * (1.0 - smoothstep(0.0, 0.35, q.y));
		col = mix(col, vec3(0.20, 0.08, 0.03), rust * 0.7);
	}
	// Kick plate: brushed steel, scratched.
	if (q.y < 0.26 && style != 3u) {
		col = vec3(0.50, 0.50, 0.49) * (0.85 + 0.2 * fs_vn(vec2(q.x * 3.0, q.y * 200.0)));
		metal = 0.85;
		rough = 0.35;
	}
	// Mail slot (not on the screen door): a brass flap with the dark slot under its lip.
	if (style != 3u) {
		vec2 ms = vec2(q.x, q.y - 1.0);
		if (abs(ms.x) < 0.15 && abs(ms.y) < 0.032) {
			col = vec3(0.55, 0.40, 0.17);
			metal = 0.9;
			rough = 0.3;
			if (abs(ms.y + 0.008) < 0.008 && abs(ms.x) < 0.125) {
				col = vec3(0.02);
				metal = 0.0;
			}
		}
	}
	// The lever and its rose, the deadbolt over it, the peephole.
	vec2 hq = vec2(q.x - handle_x, q.y - 1.02);
	float rose = length(hq) - 0.03;
	float lever = max(abs(hq.x + hinge_side * 0.055) - 0.06, abs(hq.y) - 0.011);
	float bolt = length(vec2(q.x - handle_x, q.y - 1.28)) - 0.026;
	float peep = length(vec2(q.x, q.y - 1.52)) - 0.008;
	if (min(min(rose, lever), min(bolt, peep)) < 0.0) {
		col = (wl_hash(key, 97u) & 1u) == 0u ? vec3(0.62, 0.62, 0.6) : vec3(0.55, 0.40, 0.17);
		metal = 0.9;
		rough = 0.25;
		if (peep < 0.0) {
			col = vec3(0.05);
		}
		// The lever stands proud: a tilt round its edge.
		slope += vec2(-hinge_side, 0.6) * 0.4 * (1.0 - smoothstep(-0.006, 0.0, lever));
	}
	// The frame's shadow on the recessed leaf, and the leaf's grime at hand height round the lever.
	float shade = (1.0 - smoothstep(0.0, 0.07, ds.y - q.y)) * 0.45 + (1.0 - smoothstep(0.0, 0.03, ds.x * 0.5 - abs(q.x))) * 0.25;
	col *= 1.0 - shade * day;
	col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.25, length(hq))) * step(metal, 0.5);
	albedo = col;
	return true;
}


// The light of a wall lamp on the wall round it: `d` metres from the lamp (x along, y up), its
// colour; strongest just under it, nothing past 3.5 m.
vec3 fs_lamp_wash(vec2 d, vec3 lamp_col) {
	float r = length(d);
	float fall = 1.0 / (1.0 + pow(r / 0.45, 2.0));
	fall *= 1.0 - smoothstep(1.6, 3.4, r);
	// A shade over the bulb: down and out is lit, the wall above it barely.
	fall *= mix(0.25, 1.0, smoothstep(0.12, -0.25, d.y));
	return lamp_col * fall;
}


// The lamp over a door: 0 a caged bulkhead, 1 a gooseneck barn light, 2 an LED wall pack.
// FacadeStreet.lamp_kind() is this; its colour is warm for the first two.
uint fs_lamp_kind(uint key) {
	return wl_hash(key, 93u) % 3u;
}


bool fs_lamp_lit(uint key) {
	return (wl_hash(key, 98u) >> 24u) < 216u;
}
