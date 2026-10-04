// Street-level interiors (VISUAL_ROADMAP #14): the room behind a shop's glass, traced per pixel.
//
// The office floors above keep room_interior() (one small box per window bay). A shop is one room
// the width of the whole shop (two to four bays), several metres deep, with its fittings in it -
// shelving, gondolas, racks, counters, tables and chairs, washers, barber chairs, a teller line, a
// tower lobby's desk and lift bank - each a box (or a row of identical boxes) the view ray is
// traced against, so it has real parallax: walk past a cafe and its tables slide behind one
// another. Nothing here is geometry; it costs no triangle and no draw call.
//
// Frame: x along the shop in metres (0 at the shop's low-u end, the same way `u` runs), y up from
// the storefront's base, z into the building from the glass. Every roll is shop_byte() of the
// shop's integer key (salts 40-45: 40 kind, 41 which end the counter is at, 42 walls, 43 fittings,
// 44 lobby, 45 depth), so a shop is the same kind of shop every time it is drawn.
// Building.SHOP_ROOM_SALT / shop_room_kind() mirror the kind roll (the smoke test compares them).
//
// Needs hash21(), shop_byte() and shop_tone() from building.gdshader, included after them.

// Room kinds. Building.ShopRoom mirrors these numbers.
const uint ROOM_RETAIL = 0u;
const uint ROOM_CLOTHING = 1u;
const uint ROOM_CAFE = 2u;
const uint ROOM_RESTAURANT = 3u;
const uint ROOM_LAUNDROMAT = 4u;
const uint ROOM_BARBER = 5u;
const uint ROOM_BANK = 6u;
const uint ROOM_LOBBY = 7u;

// Surface ids the trace returns. The room's own surfaces, then the fittings.
const int SI_BACK = 1;
const int SI_SIDE = 2;
const int SI_FLOOR = 3;
const int SI_CEIL = 4;
const int SI_SHELF = 10;    // wall shelving full of products (front face)
const int SI_GONDOLA = 11;  // a freestanding shelf run, products down both sides
const int SI_COUNTER = 12;  // a counter: top, front panel
const int SI_RACK = 13;     // a clothes rail with garments hanging on it
const int SI_TABLE = 14;    // a table top
const int SI_LEG = 15;      // a pedestal or a chair frame: dark metal
const int SI_SEAT = 16;     // a chair seat or back, a banquette, a barber chair
const int SI_PENDANT = 17;  // a pendant lamp shade, lit
const int SI_WASHER = 18;   // a washer or dryer front with its porthole
const int SI_CLOTH = 19;    // a tablecloth
const int SI_DESK = 20;     // a reception desk or teller counter
const int SI_PLANTER = 21;  // a planter box
const int SI_FOLIAGE = 22;  // the plant in it
const int SI_COLUMN = 23;   // a stone column
const int SI_CUBBY = 24;    // wall cubbies of folded clothes
const int SI_FIGURE = 25;   // a mannequin in the window

// 0..1 from a shop's byte.
float shop_unit(uint key, uint salt) {
	return float(shop_byte(key, salt)) / 255.0;
}

// The kind of room a shop is. Building.shop_room_kind() is this, line for line.
uint shop_room_kind(uint key) {
	uint b = shop_byte(key, 40u);
	if (b < 74u) return ROOM_RETAIL;
	if (b < 118u) return ROOM_CLOTHING;
	if (b < 162u) return ROOM_CAFE;
	if (b < 194u) return ROOM_RESTAURANT;
	if (b < 214u) return ROOM_LAUNDROMAT;
	if (b < 236u) return ROOM_BARBER;
	return ROOM_BANK;
}

// What lights the room: a cafe or a restaurant is warm, a laundromat cold, a bank and a lobby
// neutral to warm, a barber's bright neutral or cool; a shop keeps its own roll (shop_tone()).
// Building.room_tone() is this, line for line (the pavement spill is the same colour).
vec3 room_tone(uint kind, uint key) {
	bool b = shop_byte(key, 2u) < 128u;
	if (kind == ROOM_CAFE || kind == ROOM_RESTAURANT) return b ? vec3(1.0, 0.70, 0.42) : vec3(1.0, 0.80, 0.58);
	if (kind == ROOM_LAUNDROMAT) return b ? vec3(0.78, 0.90, 1.0) : vec3(1.0, 0.97, 0.92);
	if (kind == ROOM_BANK || kind == ROOM_LOBBY) return b ? vec3(1.0, 0.91, 0.78) : vec3(1.0, 0.80, 0.58);
	if (kind == ROOM_BARBER) return b ? vec3(1.0, 0.97, 0.92) : vec3(0.78, 0.90, 1.0);
	return shop_tone(key);
}

// Product packaging: every colour a supermarket shelf has, a little greyed, never neon.
vec3 product_color(float h) {
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
	c = mix(vec3(dot(c, vec3(0.333))), c, 0.75);
	float light = hash21(vec2(h * 91.0, 3.3));
	return c * mix(0.35, 0.95, light) + (light > 0.85 ? vec3(0.25) : vec3(0.0));
}

// A row of identical boxes: the slab lo..hi in y and z, items `width` wide every `period` metres
// along x from lo.x (centred in each period), up to hi.x. One slab test, then the analytic step to
// the next item's near side, so a whole row of tables is one call, not one per table. Updates the
// nearest hit (best, its normal, id and the item's index along the row).
void shop_row(vec3 ro, vec3 rd, vec3 inv, vec3 lo, vec3 hi, float period, float width, int id,
		inout float best, inout vec3 bn, inout int bid, inout float bcell) {
	vec3 t0 = (lo - ro) * inv;
	vec3 t1 = (hi - ro) * inv;
	vec3 tmn = min(t0, t1);
	vec3 tmx = max(t0, t1);
	float ta = max(max(tmn.x, tmn.y), max(tmn.z, 0.0));
	float tb = min(min(tmx.x, tmx.y), tmx.z);
	if (tb <= ta || ta >= best) {
		return;
	}
	vec3 n = ta == tmn.x ? vec3(-sign(rd.x), 0.0, 0.0) : (ta == tmn.y ? vec3(0.0, -sign(rd.y), 0.0) : vec3(0.0, 0.0, -sign(rd.z)));
	float xa = ro.x + rd.x * ta - lo.x;
	float k = floor(xa / period);
	float fx = xa - k * period;
	float a = (period - width) * 0.5;
	float b = a + width;
	if (fx >= a && fx <= b) {
		best = ta;
		bn = n;
		bid = id;
		bcell = k;
		return;
	}
	float tx = 1e9;
	float cell = k;
	if (rd.x > 1e-5) {
		float edge = fx < a ? a : period + a;
		cell = fx < a ? k : k + 1.0;
		tx = ta + (edge - fx) / rd.x;
	} else if (rd.x < -1e-5) {
		float edge = fx > b ? b : b - period;
		cell = fx > b ? k : k - 1.0;
		tx = ta + (edge - fx) / rd.x;
	}
	if (tx < tb && tx < best) {
		best = tx;
		bn = vec3(-sign(rd.x), 0.0, 0.0);
		bid = id;
		bcell = cell;
	}
}

// One box.
void shop_box(vec3 ro, vec3 rd, vec3 inv, vec3 lo, vec3 hi, int id,
		inout float best, inout vec3 bn, inout int bid, inout float bcell) {
	shop_row(ro, rd, inv, lo, hi, max(hi.x - lo.x, 1e-3), max(hi.x - lo.x, 1e-3), id, best, bn, bid, bcell);
}

// A row of boxes repeated along z (into the room): the same trace with x and z swapped.
void shop_row_z(vec3 ro, vec3 rd, vec3 inv, vec3 lo, vec3 hi, float period, float width, int id,
		inout float best, inout vec3 bn, inout int bid, inout float bcell) {
	vec3 n = bn.zyx;
	shop_row(ro.zyx, rd.zyx, inv.zyx, lo.zyx, hi.zyx, period, width, id, best, n, bid, bcell);
	bn = n.zyx;
}

// 1 under an item of a row (its footprint, softened), for the contact shadow on the floor.
float shop_foot(vec2 p, vec2 lo, vec2 hi, float period, float width, float soft) {
	float fx = mod(p.x - lo.x, period) - period * 0.5;
	float dx = abs(fx) - width * 0.5;
	float dz = max(lo.y - p.y, p.y - hi.y);
	float d = max(dx, dz);
	float inside = step(lo.x - soft, p.x) * step(p.x, hi.x + soft);
	return (1.0 - smoothstep(-soft * 0.3, soft, d)) * inside;
}

// Shelves of products on a face: shelf lines every `pitch` metres, packs of rolled widths and
// heights between them, faded to their average once a pack is under a pixel.
vec3 shelf_face(vec2 q, float pitch, float seed_k, float px, out float edge) {
	float row = floor(q.y / pitch);
	float fy = fract(q.y / pitch);
	float pack_w = mix(0.07, 0.18, hash21(vec2(row, seed_k)));
	float slot = floor(q.x / pack_w + hash21(vec2(seed_k, row)) * 7.0);
	float fx = fract(q.x / pack_w + hash21(vec2(seed_k, row)) * 7.0);
	float h = hash21(vec2(slot, row * 3.1 + seed_k));
	// Runs of the same product, a few packs wide: a real shelf is facings, not confetti.
	float run = floor(slot / mix(2.0, 6.0, hash21(vec2(row, seed_k * 1.7))));
	vec3 pack = product_color(hash21(vec2(run, row + seed_k * 13.0)));
	float top = mix(0.55, 0.88, hash21(vec2(run, row * 7.0 + seed_k)));
	float gap = step(0.08, fx) * step(fx, 0.94);
	float in_pack = step(0.08, fy) * step(fy, top) * gap;
	// Under a pixel the packs are an average: a coloured band with a darker gap over it.
	float fine = 1.0 - smoothstep(0.01, 0.035, px);
	in_pack = mix(0.62, in_pack, fine);
	pack = mix(product_color(hash21(vec2(row, seed_k))) * 0.8 + 0.08, pack, fine);
	vec3 back = vec3(0.10, 0.10, 0.11);
	vec3 c = mix(back, pack * (0.75 + 0.25 * fy / top), in_pack);
	// The shelf's own edge: a pale price rail at the foot of each shelf.
	edge = step(fy, 0.06);
	c = mix(c, vec3(0.72, 0.72, 0.70), edge);
	return c;
}

// Garments on a rail: hangers' worth of slices, a few colours a rail, a ragged hem.
vec3 garment_face(vec2 q, float rack, float seed_k, float px, float top) {
	float slice = floor(q.x / 0.07);
	float h = hash21(vec2(slice, rack + seed_k));
	vec3 c0 = product_color(hash21(vec2(rack, seed_k)));
	vec3 c1 = mix(vec3(0.08), vec3(0.85, 0.83, 0.80), hash21(vec2(rack, seed_k + 4.0)));
	vec3 c2 = product_color(hash21(vec2(rack * 3.0, seed_k + 9.0))) * 0.6;
	vec3 c = h < 0.45 ? c0 : (h < 0.8 ? c1 : c2);
	float fold = fract(q.x / 0.07);
	c *= 0.72 + 0.28 * smoothstep(0.0, 0.5, fold) * (1.0 - smoothstep(0.6, 1.0, fold));
	// Hems at different lengths: below its hem a slice is the dark of the rack behind it.
	float hem = mix(0.15, 0.55, hash21(vec2(slice, rack * 1.3 + seed_k)));
	float fine = 1.0 - smoothstep(0.01, 0.03, px);
	float cloth = mix(0.75, step(hem, q.y), fine);
	c = mix(vec3(0.05), c, cloth);
	// The rail and the hangers' hooks over it.
	c = mix(c, vec3(0.55, 0.55, 0.56), step(top - 0.04, q.y));
	return c;
}

// The room behind a shop's glass. `ro` is where the view ray crosses the pane (shop frame), `rd`
// the ray, `wide` the shop's width, `high` its ceiling, `deep` its depth. `px` is metres a pixel
// covers at the glass, `dist` the camera's distance to it. Returns the surface's colour as lit by
// the day coming in at the front (the caller scales it by the interior exposure), and in `lamp`
// how much the shop's own lights fall there (the caller tints it by shop_tone() after dark, and a
// little by day: a shop is lit inside all day), in `glow` light the fittings give off themselves -
// pendants, a fridge, a till, a lift's indicator - and in `depth_t` how far in the hit is (0..2).
vec3 shop_interior(vec3 ro, vec3 rd, float wide, float high, float deep, uint key, uint kind,
		float px, float dist, out float depth_t, out float lamp, out vec3 glow) {
	glow = vec3(0.0);
	vec3 inv = 1.0 / mix(rd, sign(rd) * 1e-5 + vec3(1e-6), lessThan(abs(rd), vec3(1e-5)));
	float W = wide;
	float H = high;
	float D = deep;
	float best = 1e8;
	vec3 bn = vec3(0.0, 0.0, -1.0);
	int bid = SI_BACK;
	float bcell = 0.0;
	// The room itself.
	if (rd.z > 1e-4) {
		float t = (D - ro.z) / rd.z;
		if (t > 0.0 && t < best) { best = t; bn = vec3(0.0, 0.0, -1.0); bid = SI_BACK; }
	}
	if (abs(rd.x) > 1e-4) {
		float t = ((rd.x > 0.0 ? W : 0.0) - ro.x) / rd.x;
		if (t > 0.0 && t < best) { best = t; bn = vec3(-sign(rd.x), 0.0, 0.0); bid = SI_SIDE; }
	}
	if (abs(rd.y) > 1e-4) {
		float t = ((rd.y > 0.0 ? H : 0.0) - ro.y) / rd.y;
		if (t > 0.0 && t < best) { best = t; bn = vec3(0.0, -sign(rd.y), 0.0); bid = rd.y > 0.0 ? SI_CEIL : SI_FLOOR; }
	}

	// Per-shop variety.
	float sk = float(key % 4093u) * 0.37;
	bool flip = shop_byte(key, 41u) < 128u;
	float wall_k = shop_unit(key, 42u);
	float var_k = shop_unit(key, 43u);

	// The fittings, kind by kind. Rows sit a pitch in from the side walls so the end of a row
	// never sticks into a wall.
	if (kind == ROOM_RETAIL) {
		shop_box(ro, rd, inv, vec3(0.25, 0.0, D - 0.45), vec3(W - 0.25, 2.15, D), SI_SHELF, best, bn, bid, bcell);
		float gp = mix(2.2, 2.7, var_k);
		float n_g = max(floor((W - 1.0) / gp), 1.0);
		float g0 = (W - n_g * gp) * 0.5;
		shop_row(ro, rd, inv, vec3(g0, 0.0, 2.3), vec3(W - g0, mix(1.35, 1.65, wall_k), D - 1.5), gp, 0.92, SI_GONDOLA, best, bn, bid, bcell);
		float cx = flip ? 0.5 : W - 2.6;
		shop_box(ro, rd, inv, vec3(cx, 0.0, 0.75), vec3(cx + 2.1, 1.0, 1.45), SI_COUNTER, best, bn, bid, bcell);
	} else if (kind == ROOM_CLOTHING) {
		shop_box(ro, rd, inv, vec3(0.25, 0.0, D - 0.42), vec3(W - 0.25, 2.3, D), SI_CUBBY, best, bn, bid, bcell);
		float rp = mix(1.9, 2.4, var_k);
		float n_r = max(floor((W - 0.8) / rp), 1.0);
		float r0 = (W - n_r * rp) * 0.5;
		shop_row(ro, rd, inv, vec3(r0, 0.42, 2.1), vec3(W - r0, 1.52, 2.55), rp, rp - 0.55, SI_RACK, best, bn, bid, bcell);
		if (D > 5.0) {
			shop_row(ro, rd, inv, vec3(r0 + rp * 0.5, 0.42, 4.0), vec3(W - r0 + rp * 0.5, 1.52, 4.45), rp, rp - 0.75, SI_RACK, best, bn, bid, bcell);
		}
		float tx = flip ? W - 2.2 : 0.7;
		shop_box(ro, rd, inv, vec3(tx, 0.0, 1.15), vec3(tx + 1.5, 0.82, 1.75), SI_COUNTER, best, bn, bid, bcell);
		// Two mannequins in the window, side on to the street like a dressed window does it.
		// Head, dressed torso to the knee, and the pole and base it stands on.
		vec3 m0 = vec3(W * 0.5 - 1.6, 0.0, 0.55);
		vec3 m1 = vec3(W * 0.5 + 1.6, 0.0, 0.85);
		shop_row(ro, rd, inv, vec3(m0.x, 1.50, 0.62), vec3(m1.x, 1.74, 0.78), 1.6, 0.17, SI_FIGURE, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(m0.x, 0.62, m0.z), vec3(m1.x, 1.47, m1.z), 1.6, 0.40, SI_FIGURE, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(m0.x, 0.0, 0.68), vec3(m1.x, 0.62, 0.72), 1.6, 0.04, SI_LEG, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(m0.x, 0.0, 0.52), vec3(m1.x, 0.03, 0.88), 1.6, 0.36, SI_LEG, best, bn, bid, bcell);
	} else if (kind == ROOM_CAFE || kind == ROOM_RESTAURANT) {
		bool cafe = kind == ROOM_CAFE;
		float tp = cafe ? 1.85 : 2.05;
		float n_t = max(floor((W - 0.6) / tp), 1.0);
		float t0 = (W - n_t * tp) * 0.5;
		float tw = cafe ? 0.68 : 0.86;
		for (int r = 0; r < 2; r++) {
			float z0 = r == 0 ? 1.15 : 3.35;
			if (r == 1 && D < 6.4) {
				break;
			}
			float x0 = t0 + (r == 1 ? tp * 0.5 * (flip ? 1.0 : 0.0) : 0.0);
			float x1 = W - t0 + (r == 1 ? tp * 0.5 * (flip ? 1.0 : 0.0) : 0.0);
			if (cafe) {
				shop_row(ro, rd, inv, vec3(x0, 0.72, z0), vec3(x1, 0.76, z0 + tw), tp, tw, SI_TABLE, best, bn, bid, bcell);
			} else {
				shop_row(ro, rd, inv, vec3(x0, 0.42, z0), vec3(x1, 0.78, z0 + tw), tp, tw + 0.04, SI_CLOTH, best, bn, bid, bcell);
			}
			shop_row(ro, rd, inv, vec3(x0, 0.0, z0 + tw * 0.5 - 0.05), vec3(x1, 0.72, z0 + tw * 0.5 + 0.05), tp, 0.10, SI_LEG, best, bn, bid, bcell);
			// Chairs on the far side of each table, facing the street; their seats and backs.
			float cz = z0 + tw + 0.12;
			shop_row(ro, rd, inv, vec3(x0, 0.44, cz), vec3(x1, 0.48, cz + 0.42), tp, 0.44, SI_SEAT, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(x0, 0.48, cz + 0.38), vec3(x1, 0.95, cz + 0.43), tp, 0.42, SI_SEAT, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(x0, 0.0, cz + 0.05), vec3(x1, 0.44, cz + 0.37), tp, 0.36, SI_LEG, best, bn, bid, bcell);
		}
		if (cafe) {
			// The counter across the back with the machine and the cakes, a back bar behind it.
			float ce = flip ? 0.4 : 1.6;
			shop_box(ro, rd, inv, vec3(ce, 0.0, D - 2.0), vec3(W - 2.0 + ce, 1.05, D - 1.35), SI_COUNTER, best, bn, bid, bcell);
			shop_box(ro, rd, inv, vec3(0.25, 0.0, D - 0.4), vec3(W - 0.25, 2.2, D), SI_SHELF, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(ce, H - 0.95, D - 1.8), vec3(W - 2.0 + ce, H - 0.7, D - 1.55), 1.15, 0.30, SI_PENDANT, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(ce, H - 0.7, D - 1.685), vec3(W - 2.0 + ce, H, D - 1.665), 1.15, 0.02, SI_LEG, best, bn, bid, bcell);
		} else {
			// A banquette along the back wall, pendants over the tables.
			shop_box(ro, rd, inv, vec3(0.25, 0.0, D - 0.75), vec3(W - 0.25, 1.15, D), SI_SEAT, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(t0, H - 1.05, 1.42), vec3(W - t0, H - 0.8, 1.72), tp, 0.34, SI_PENDANT, best, bn, bid, bcell);
			shop_row(ro, rd, inv, vec3(t0, H - 0.8, 1.56), vec3(W - t0, H, 1.58), tp, 0.02, SI_LEG, best, bn, bid, bcell);
		}
	} else if (kind == ROOM_LAUNDROMAT) {
		shop_row(ro, rd, inv, vec3(0.3, 0.0, D - 0.78), vec3(W - 0.3, 0.95, D), 0.78, 0.72, SI_WASHER, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(0.3, 1.05, D - 0.78), vec3(W - 0.3, 1.98, D), 0.78, 0.72, SI_WASHER, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(1.17, 0.0, 2.9), vec3(W - 1.17, 0.95, 4.3), 0.78, 0.72, SI_WASHER, best, bn, bid, bcell);
		shop_box(ro, rd, inv, vec3(1.2, 0.86, 1.25), vec3(W - 1.2, 0.92, 1.95), SI_TABLE, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(1.2, 0.0, 1.55), vec3(W - 1.2, 0.86, 1.65), max(W - 2.4, 0.5) / 2.0, 0.08, SI_LEG, best, bn, bid, bcell);
	} else if (kind == ROOM_BARBER) {
		shop_box(ro, rd, inv, vec3(0.25, 0.0, D - 0.45), vec3(W - 0.25, 0.9, D), SI_COUNTER, best, bn, bid, bcell);
		float bp = 1.65;
		float n_b = max(floor((W - 0.6) / bp), 1.0);
		float b0 = (W - n_b * bp) * 0.5;
		shop_row(ro, rd, inv, vec3(b0, 0.0, D - 1.62), vec3(W - b0, 0.42, D - 1.28), bp, 0.22, SI_LEG, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(b0, 0.42, D - 1.85), vec3(W - b0, 0.62, D - 1.05), bp, 0.62, SI_SEAT, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(b0, 0.62, D - 1.85), vec3(W - b0, 1.32, D - 1.72), bp, 0.56, SI_SEAT, best, bn, bid, bcell);
		float wx = flip ? 0.4 : W * 0.5;
		shop_box(ro, rd, inv, vec3(wx, 0.0, 0.85), vec3(wx + W * 0.5 - 0.4, 0.46, 1.35), SI_SEAT, best, bn, bid, bcell);
	} else if (kind == ROOM_BANK) {
		shop_box(ro, rd, inv, vec3(0.35, 0.0, D - 3.0), vec3(W - 0.35, 1.08, D - 2.3), SI_DESK, best, bn, bid, bcell);
		float dx = flip ? 0.6 : W - 2.2;
		shop_box(ro, rd, inv, vec3(dx, 0.0, 1.3), vec3(dx + 1.6, 0.76, 2.1), SI_TABLE, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(dx, 0.0, 1.38), vec3(dx + 1.6, 0.74, 2.02), 0.8, 0.06, SI_LEG, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(W * 0.5 - 1.0, 0.0, 2.3), vec3(W * 0.5 + 1.0, 0.95, 2.36), 0.5, 0.04, SI_LEG, best, bn, bid, bcell);
	} else {
		// A tower lobby: double height, columns, planters, the desk, a lift bank at the back.
		shop_row(ro, rd, inv, vec3(0.0, 0.0, D * 0.3), vec3(W, H, D * 0.3 + 0.75), W / 3.0, 0.75, SI_COLUMN, best, bn, bid, bcell);
		shop_box(ro, rd, inv, vec3(W * 0.5 - 1.9, 0.0, D * 0.55), vec3(W * 0.5 + 1.9, 1.12, D * 0.55 + 0.85), SI_DESK, best, bn, bid, bcell);
		// A planter against each side wall beside the desk, a long bench between the columns.
		float pp = W - 1.7;
		shop_row(ro, rd, inv, vec3(0.85 - pp * 0.5, 0.0, D * 0.52), vec3(0.85 + pp * 1.5, 0.75, D * 0.52 + 0.9), pp, 0.9, SI_PLANTER, best, bn, bid, bcell);
		shop_row(ro, rd, inv, vec3(0.85 - pp * 0.5, 0.75, D * 0.52 + 0.1), vec3(0.85 + pp * 1.5, mix(2.0, 2.8, var_k), D * 0.52 + 0.8), pp, 0.8, SI_FOLIAGE, best, bn, bid, bcell);
		shop_box(ro, rd, inv, vec3(W * 0.5 - 1.3, 0.0, 2.0), vec3(W * 0.5 + 1.3, 0.44, 2.55), SI_SEAT, best, bn, bid, bcell);
	}

	vec3 p = ro + rd * best;
	depth_t = clamp(p.z / max(D, 0.01), 0.0, 2.0);
	float px_in = px * (dist + best) / max(dist, 0.5);
	float fine = 1.0 - smoothstep(0.012, 0.04, px_in);

	// The shop's surfaces.
	vec3 wall = mix(vec3(0.80, 0.78, 0.74), vec3(0.62, 0.58, 0.52), wall_k);
	if (wall_k > 0.78) {
		wall = mix(vec3(0.28, 0.33, 0.30), vec3(0.42, 0.30, 0.24), fract(wall_k * 7.0));
	}
	vec3 floor_col;
	if (kind == ROOM_CAFE || kind == ROOM_RESTAURANT || kind == ROOM_CLOTHING) {
		// Planks.
		float plank = floor(p.x / 0.16);
		float joint = step(fract(p.x / 0.16), 0.06) + step(fract(p.z / 1.2 + hash21(vec2(plank, 2.0))), 0.02);
		floor_col = mix(vec3(0.36, 0.24, 0.15), vec3(0.50, 0.37, 0.25), hash21(vec2(plank, sk)));
		floor_col *= mix(1.0, 0.7, clamp(joint, 0.0, 1.0) * fine);
		if (kind == ROOM_CLOTHING && var_k > 0.5) {
			floor_col = vec3(0.55, 0.54, 0.52) * (0.9 + 0.1 * hash21(floor(p.xz * 0.5) + sk));
		}
	} else if (kind == ROOM_LAUNDROMAT || kind == ROOM_BARBER) {
		// Checkerboard vinyl.
		vec2 c = floor(p.xz / 0.3);
		float chk = mod(c.x + c.y, 2.0);
		floor_col = mix(vec3(0.78, 0.78, 0.76), vec3(0.08, 0.08, 0.09), mix(0.5, chk, fine));
	} else if (kind == ROOM_BANK || kind == ROOM_LOBBY) {
		// Polished stone in big slabs.
		vec2 c = floor(p.xz / 1.2);
		float chk = mod(c.x + c.y, 2.0);
		vec3 s0 = wall_k < 0.5 ? vec3(0.74, 0.71, 0.66) : vec3(0.20, 0.20, 0.21);
		floor_col = mix(s0, s0 * 0.78, chk * 0.6) * (0.92 + 0.12 * hash21(c + sk));
		floor_col *= mix(1.0, 0.75, step(min(fract(p.x / 1.2), fract(p.z / 1.2)), 0.008) * fine);
	} else {
		// Vinyl tile.
		vec2 c = floor(p.xz / 0.6);
		floor_col = vec3(0.66, 0.65, 0.62) * (0.92 + 0.10 * hash21(c + sk));
		floor_col *= mix(1.0, 0.8, step(min(fract(p.x / 0.6), fract(p.z / 0.6)), 0.03) * fine);
	}

	vec3 col = wall;
	// How much of the fitting's own light falls here (before the shop's colour), and the ceiling
	// fixtures, which are part of what the room looks like lit.
	float fix_lamp = 0.0;
	if (bid == SI_BACK || bid == SI_SIDE) {
		col = wall * (bid == SI_SIDE ? 0.82 : 0.95);
		float along_w = bid == SI_BACK ? p.x : p.z;
		// A wainscot under a rail, in a darker paint or timber, and a skirting.
		if (kind == ROOM_CAFE || kind == ROOM_RESTAURANT || kind == ROOM_BARBER) {
			vec3 dado = wall_k > 0.5 ? vec3(0.30, 0.20, 0.13) : wall * vec3(0.55, 0.62, 0.60);
			col = mix(col, dado, step(p.y, 1.05));
			col = mix(col, dado * 0.6, step(abs(p.y - 1.06), 0.025) * fine);
		}
		col *= mix(1.0, 0.55, step(p.y, 0.1));
		// What hangs on the walls: framed pictures and posters in a cafe, a restaurant, a barber's
		// or a clothes shop, rolled per 1.6 m slot; shelving down a shop's side walls.
		if (kind == ROOM_RETAIL && bid == SI_SIDE && p.y < 2.1) {
			float e;
			col = shelf_face(vec2(p.z, p.y), 0.40, sk + 7.0 + sign(rd.x), px_in, e) * 0.92;
		} else if (kind != ROOM_LOBBY && kind != ROOM_BANK && kind != ROOM_LAUNDROMAT) {
			float slot = floor(along_w / 1.6);
			float pick = hash21(vec2(slot, sk + float(bid) * 3.0));
			vec2 c = vec2(fract(along_w / 1.6) - 0.5, p.y - 1.85) * vec2(1.6, 1.0);
			vec2 half_s = pick < 0.45 ? vec2(0.32, 0.24) : vec2(0.22, 0.32);
			vec2 d = abs(c) - half_s;
			if (pick < 0.7 && max(d.x, d.y) < 0.0) {
				bool frame_px = max(d.x, d.y) > -0.035;
				vec3 art = product_color(hash21(vec2(slot, sk + 17.0))) * mix(0.5, 0.9, hash21(vec2(floor(c.y / 0.12), slot)));
				col = frame_px ? mix(vec3(0.06), vec3(0.62, 0.48, 0.25), step(0.5, pick)) : art;
			}
		}
		if (kind == ROOM_LOBBY || kind == ROOM_BANK) {
			float along = along_w;
			vec3 stone = kind == ROOM_LOBBY ? mix(vec3(0.62, 0.58, 0.52), vec3(0.16, 0.15, 0.15), step(0.6, wall_k)) : vec3(0.42, 0.28, 0.18);
			col = stone * (0.9 + 0.12 * hash21(vec2(floor(along / 1.2), floor(p.y / 2.4)) + sk));
			col *= mix(1.0, 0.6, step(min(fract(along / 1.2), fract(p.y / 2.4)), 0.006) * fine);
		}
		if (bid == SI_BACK && kind == ROOM_LOBBY) {
			// The lift bank: brushed steel doors in frames, an indicator over each.
			float lp = 2.1;
			float lx = mod(p.x - W * 0.5 + lp * 0.5, lp);
			bool door = abs(lx - lp * 0.5) < 0.6 && p.y < 2.5;
			bool frame = abs(lx - lp * 0.5) < 0.72 && p.y < 2.65 && !door;
			if (door) {
				col = vec3(0.55, 0.56, 0.58) * (0.85 + 0.15 * step(0.01, abs(lx - lp * 0.5)));
				col *= 0.9 + 0.1 * fract(p.y * 13.0 + hash21(vec2(floor(p.x / lp), 3.0)));
			} else if (frame) {
				col = vec3(0.30, 0.30, 0.31);
			}
			float ind = (1.0 - smoothstep(0.06, 0.1, abs(lx - lp * 0.5))) * step(2.75, p.y) * step(p.y, 2.85);
			glow += vec3(1.0, 0.55, 0.18) * ind * 2.0;
		}
		if (bid == SI_BACK && kind == ROOM_BARBER) {
			// The mirror over the counter, one per chair: it shows the lit room, so it reads
			// as a bright grey-blue sheet with a frame.
			float mp = 1.65;
			float mx = abs(mod(p.x - (W - floor((W - 0.6) / mp) * mp) * 0.5, mp) - mp * 0.5);
			if (mx < 0.55 && p.y > 1.0 && p.y < 2.15) {
				col = mix(vec3(0.42, 0.46, 0.50), vec3(0.75, 0.78, 0.80), smoothstep(1.0, 2.1, p.y + rd.x * 0.3));
				fix_lamp = 0.6;
			} else if (mx < 0.62 && p.y > 0.95 && p.y < 2.2) {
				col = vec3(0.10);
			}
		}
		if (bid == SI_BACK && kind == ROOM_RESTAURANT) {
			// Framed pictures over the banquette.
			float fp = 1.4;
			float fx = abs(mod(p.x, fp) - fp * 0.5);
			if (fx < 0.4 && abs(p.y - 1.75) < 0.3) {
				col = fx < 0.34 && abs(p.y - 1.75) < 0.24 ? product_color(hash21(vec2(floor(p.x / fp), sk))) * 0.6 : vec3(0.75, 0.6, 0.3);
			}
		}
	} else if (bid == SI_FLOOR) {
		col = floor_col;
	} else if (bid == SI_CEIL) {
		col = vec3(0.74, 0.73, 0.70);
		// Fittings: fluorescent runs in a shop or a laundromat, downlights elsewhere, linear
		// slots across a lobby's high ceiling.
		if (kind == ROOM_RETAIL || kind == ROOM_LAUNDROMAT) {
			float lx = abs(fract(p.x / 2.4) - 0.5) * 2.4;
			fix_lamp = (1.0 - smoothstep(0.07, 0.12, lx)) * step(0.8, p.z) * step(p.z, D - 0.6);
		} else if (kind == ROOM_LOBBY) {
			float lz = abs(fract(p.z / 2.5) - 0.5) * 2.5;
			fix_lamp = 1.0 - smoothstep(0.04, 0.08, lz);
		} else {
			vec2 g = abs(fract(p.xz / vec2(1.6, 1.8)) - 0.5) * vec2(1.6, 1.8);
			fix_lamp = 1.0 - smoothstep(0.06, 0.10, length(g));
		}
		col = mix(col, vec3(1.0), fix_lamp);
		glow += vec3(1.0, 0.95, 0.88) * fix_lamp * 0.35;
	} else if (bid == SI_SHELF) {
		float e;
		vec2 q = vec2(p.x, p.y);
		col = shelf_face(q, 0.40, sk + 1.0, px_in, e);
		if (bn.y > 0.5) {
			col = vec3(0.25);
		}
		// A grocer's back wall is chillers: a cool glow behind the doors.
		if (kind == ROOM_RETAIL && var_k > 0.55 && bn.z < -0.5) {
			glow += vec3(0.75, 0.88, 1.0) * (0.12 + 0.6 * e) * step(p.y, 2.05);
			col = mix(col, col * 1.2 + 0.05, 0.5);
		}
		if (kind == ROOM_CAFE && bn.z < -0.5) {
			// The back bar: bottles and cups on shelves, a menu board over them.
			if (p.y > 1.55) {
				col = vec3(0.06, 0.07, 0.065);
				float line = step(0.5, fract(p.y / 0.07)) * step(0.3, hash21(vec2(floor(p.x / 0.25), floor(p.y / 0.07))));
				col = mix(col, vec3(0.85), line * 0.6 * fine + 0.04 * (1.0 - fine));
			}
		}
	} else if (bid == SI_GONDOLA) {
		float e;
		if (abs(bn.x) > 0.5) {
			col = shelf_face(vec2(p.z, p.y), 0.38, sk + bcell * 5.0 + sign(bn.x), px_in, e);
		} else if (bn.z < -0.5) {
			// The end cap toward the street: a promotion, stacked high.
			col = shelf_face(vec2(p.x * 1.6, p.y), 0.30, sk + bcell * 11.0 + 3.0, px_in, e);
			col = mix(col, product_color(hash21(vec2(bcell, sk + 2.0))), step(1.2, p.y) * 0.6);
		} else {
			col = vec3(0.30, 0.30, 0.31);
		}
	} else if (bid == SI_COUNTER) {
		vec3 front = mix(vec3(0.16, 0.12, 0.09), vec3(0.72, 0.70, 0.66), step(0.5, var_k));
		if (kind == ROOM_CAFE) {
			front = mix(vec3(0.30, 0.20, 0.13), vec3(0.20, 0.30, 0.32), step(0.6, wall_k));
		}
		col = bn.y > 0.5 ? vec3(0.62, 0.60, 0.57) : front;
		// The till, the coffee machine: something small and lit on the top.
		if (bn.y > 0.5 && kind != ROOM_BARBER) {
			float s = step(abs(fract(p.x / 1.7) - 0.5), 0.12);
			col = mix(col, vec3(0.08), s);
		}
		if (bn.z < -0.5 && p.y > 0.95) {
			col = vec3(0.70, 0.68, 0.64);
		}
		if (kind == ROOM_CAFE && bn.y > 0.5) {
			// A lit cake case along the counter's front edge.
			glow += vec3(1.0, 0.86, 0.66) * 0.25 * step(abs(p.x - W * 0.5), 0.8);
		}
	} else if (bid == SI_CUBBY) {
		// Square cubbies of folded clothes in stacks.
		vec2 c = floor(vec2(p.x / 0.5, p.y / 0.42));
		vec2 f = fract(vec2(p.x / 0.5, p.y / 0.42));
		float stack = step(0.08, f.x) * step(f.x, 0.92) * step(0.06, f.y) * step(f.y, mix(0.5, 0.85, hash21(c + sk)));
		vec3 cloth = product_color(hash21(c * 1.3 + sk)) * mix(0.6, 1.0, step(0.5, fract(f.y * 7.0)));
		col = mix(vec3(0.82, 0.80, 0.76), cloth, mix(0.5, stack, fine));
		if (bn.y > 0.5) {
			col = vec3(0.82, 0.80, 0.76);
		}
	} else if (bid == SI_RACK) {
		float top = 1.52 - 0.42;
		if (abs(bn.z) > 0.5) {
			col = garment_face(vec2(p.x, p.y - 0.42), bcell + floor(p.z), sk, px_in, top);
		} else if (bn.y > 0.5) {
			col = vec3(0.35, 0.35, 0.36);
		} else {
			col = product_color(hash21(vec2(bcell, sk))) * 0.45;
		}
	} else if (bid == SI_TABLE) {
		col = bn.y > 0.5 ? mix(vec3(0.45, 0.31, 0.20), vec3(0.80, 0.79, 0.76), step(0.55, var_k)) : vec3(0.20, 0.15, 0.11);
		if (kind == ROOM_LAUNDROMAT || kind == ROOM_BANK) {
			col = bn.y > 0.5 ? vec3(0.70, 0.70, 0.68) : vec3(0.40, 0.40, 0.42);
		}
		// A cup, a plate, a laptop: one small thing on each top.
		if (bn.y > 0.5) {
			float th = hash21(vec2(bcell, sk + 7.0));
			vec2 c = vec2(fract((p.x) / 1.85) - 0.5, p.z - 1.5);
			col = mix(col, th < 0.5 ? vec3(0.92) : vec3(0.12), (1.0 - smoothstep(0.05, 0.07, length(c - vec2(th - 0.5, 0.0) * 0.4))) * fine);
		}
	} else if (bid == SI_CLOTH) {
		col = mix(vec3(0.88, 0.87, 0.84), vec3(0.45, 0.12, 0.10), step(0.75, var_k));
		col *= bn.y > 0.5 ? 1.0 : (0.80 + 0.12 * step(0.5, fract(p.x / 0.09)));
	} else if (bid == SI_LEG) {
		col = vec3(0.07, 0.07, 0.075);
	} else if (bid == SI_SEAT) {
		vec3 seat = kind == ROOM_LOBBY ? vec3(0.10, 0.09, 0.085) : kind == ROOM_BARBER ? mix(vec3(0.05), vec3(0.42, 0.06, 0.05), step(0.5, var_k))
			: (kind == ROOM_RESTAURANT ? vec3(0.32, 0.08, 0.07) : mix(vec3(0.35, 0.24, 0.15), vec3(0.12, 0.13, 0.14), step(0.5, wall_k)));
		col = seat * (bn.y > 0.5 ? 1.15 : 0.9);
		if (kind == ROOM_RESTAURANT && bn.z < -0.5 && p.z > D - 1.0) {
			// The banquette's buttoned back.
			vec2 b = abs(fract(vec2(p.x / 0.3, p.y / 0.3)) - 0.5);
			col *= mix(1.0, 0.7, (1.0 - smoothstep(0.05, 0.1, length(b))) * step(0.5, p.y) * fine);
		}
	} else if (bid == SI_PENDANT) {
		// A dark metal shade, the bulb's glow showing under it.
		col = mix(vec3(0.05), vec3(0.45, 0.32, 0.15), step(0.5, var_k));
		if (bn.y < -0.5) {
			glow += vec3(1.0, 0.72, 0.42) * 4.0;
			col = vec3(1.0, 0.9, 0.7);
		}
	} else if (bid == SI_WASHER) {
		col = mix(vec3(0.86, 0.87, 0.88), vec3(0.62, 0.63, 0.65), step(0.5, var_k));
		if (abs(bn.z) > 0.5) {
			// The porthole: chrome ring, dark glass with a glint, the control strip over it.
			float local_x = mod(p.x - 0.3, 0.78) - 0.39;
			float yb = p.y < 1.0 ? 0.0 : 1.05;
			vec2 c = vec2(local_x, p.y - yb - 0.47);
			float r = length(c);
			col = mix(col, vec3(0.75, 0.76, 0.78), 1.0 - smoothstep(0.24, 0.255, r));
			vec3 drum = mix(vec3(0.05, 0.06, 0.07), product_color(hash21(vec2(floor(p.x / 0.78), yb + sk))) * 0.35, step(0.6, hash21(vec2(floor(p.x / 0.78), yb + sk * 3.0))));
			col = mix(col, drum, 1.0 - smoothstep(0.19, 0.205, r));
			float strip = step(p.y - yb, 0.88) * step(0.78, p.y - yb);
			col = mix(col, vec3(0.2), strip);
			float led = strip * step(abs(local_x - 0.22), 0.04);
			glow += mix(vec3(0.2, 1.0, 0.4), vec3(1.0, 0.25, 0.1), step(0.7, hash21(vec2(floor(p.x / 0.78), yb)))) * led * 1.5;
		}
	} else if (bid == SI_DESK) {
		vec3 face = kind == ROOM_LOBBY ? mix(vec3(0.68, 0.64, 0.58), vec3(0.25, 0.18, 0.12), step(0.5, var_k)) : vec3(0.36, 0.24, 0.15);
		col = bn.y > 0.5 ? vec3(0.78, 0.76, 0.72) : face * (0.9 + 0.1 * step(0.5, fract(p.x / 0.9)));
		// The light strip under the desk's top lip.
		float lip = step(abs(p.y - 0.98), 0.025) * step(0.5, abs(bn.z));
		glow += vec3(1.0, 0.85, 0.65) * lip * 1.5;
		if (kind == ROOM_BANK && bn.y > 0.5) {
			// Teller screens: a monitor glow at each window.
			glow += vec3(0.6, 0.75, 1.0) * 0.4 * step(abs(fract(p.x / 1.5) - 0.5), 0.12);
		}
	} else if (bid == SI_PLANTER) {
		col = vec3(0.20, 0.20, 0.21);
	} else if (bid == SI_FOLIAGE) {
		// Leaves in clumps with shadow between them, darker toward the pot and the edges.
		vec2 lq = vec2(p.x + p.z, p.y);
		float leaf = hash21(floor(lq / 0.08) + sk);
		float clump = hash21(floor(lq / 0.3) + sk * 1.7);
		col = mix(vec3(0.03, 0.06, 0.02), vec3(0.17, 0.31, 0.10), mix(0.45, leaf * (0.4 + 0.6 * clump), fine));
		col *= bn.y > 0.5 ? 1.15 : 0.85;
	} else if (bid == SI_COLUMN) {
		col = mix(vec3(0.70, 0.67, 0.62), vec3(0.22, 0.21, 0.21), step(0.6, wall_k));
		col *= 0.92 + 0.1 * hash21(vec2(bcell, floor(p.y / 1.5)) + sk);
	} else if (bid == SI_FIGURE) {
		// A dressed mannequin: a pale head, a garment from the shoulders to the knees.
		vec3 dress = product_color(hash21(vec2(bcell, sk + 5.0)));
		col = p.y > 1.48 ? vec3(0.86, 0.84, 0.80) : dress * (0.85 + 0.15 * step(1.1, p.y));
	}

	// Contact shadows on the floor under the fittings near the glass.
	if (bid == SI_FLOOR) {
		float sh = 0.0;
		if (kind == ROOM_RETAIL) {
			float gp = mix(2.2, 2.7, var_k);
			float g0 = (W - max(floor((W - 1.0) / gp), 1.0) * gp) * 0.5;
			sh = shop_foot(p.xz, vec2(g0, 2.3), vec2(W - g0, D - 1.5), gp, 0.92, 0.25);
		} else if (kind == ROOM_CAFE || kind == ROOM_RESTAURANT) {
			float tp = kind == ROOM_CAFE ? 1.85 : 2.05;
			float t0 = (W - max(floor((W - 0.6) / tp), 1.0) * tp) * 0.5;
			sh = shop_foot(p.xz, vec2(t0, 1.0), vec2(W - t0, 2.6), tp, 0.7, 0.3) * 0.7;
		} else if (kind == ROOM_LAUNDROMAT) {
			sh = shop_foot(p.xz, vec2(1.17, 2.9), vec2(W - 1.17, 4.3), 0.78, 0.78, 0.2);
		}
		// The foot of every wall.
		float wall_d = min(min(p.x, W - p.x), D - p.z);
		col *= mix(0.62, 1.0, smoothstep(0.0, 0.45, wall_d)) * (1.0 - 0.5 * sh);
	}

	// Light. The day comes in at the front: faces toward the street and tops catch it, the back
	// of the room gets less. The shop's own fittings light tops and the upper walls.
	float face_day = 0.58 + 0.30 * max(-bn.z, 0.0) + 0.22 * max(bn.y, 0.0) - 0.25 * max(-bn.y, 0.0);
	float into = clamp(p.z / max(D, 0.01), 0.0, 1.0);
	float day = face_day * mix(1.0, 0.42, into);
	float up_k = clamp(p.y / max(H, 0.01), 0.0, 1.0);
	lamp = 0.42 + 0.45 * max(bn.y, 0.0) + 0.22 * max(-bn.z, 0.0) + 0.18 * up_k;
	lamp *= mix(1.0, 0.75, into);
	if (bid == SI_CEIL) {
		lamp = 0.45 + 2.4 * fix_lamp;
	} else if (fix_lamp > 0.0) {
		lamp += fix_lamp;
	}
	// A lobby is mostly light stone and lit high: a little brighter in its own right.
	if (kind == ROOM_LOBBY) {
		lamp *= 1.15;
	}
	return col * day;
}
