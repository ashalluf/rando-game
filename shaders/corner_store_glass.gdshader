// The corner store's glass while the real interior is hidden (CornerStoreSite: the player and the
// camera are away from the door): the room behind the glass TRACED per pixel from the very numbers
// the geometry is built from (CornerStore.layout(): the back shelving, the gondolas running back
// from the window, the coolers down one wall, the counter and the cigarette rack on the other, the
// drop ceiling's light panels, the tile floor), so walking up to the door swaps the trace for the
// real thing with nothing jumping. Opaque: the pane writes depth and the room is emitted behind
// the glass's own reflection. No triangle, one draw. Works in linear on both renderers.
//
// Frame: the store's own (x across, y up from the floor, z out of the front face; the room is
// z < 0). `to_store` takes the pane's model space there (identity for the windows, the hinge's
// transform for the door's leaf).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/color_space.gdshaderinc"

uniform mat4 to_store = mat4(1.0);
// Interior box: x0, x1, z0 (back), z1 (front).
uniform vec4 room = vec4(-5.0, 5.0, -10.0, -0.25);
uniform float ceiling = 3.0;
uniform float back_depth = 0.45;
uniform float back_height = 2.1;
// The coolers: x from the wall to their face, z from front to back, height.
uniform vec4 cooler = vec4(-5.0, -4.15, -2.0, -8.0);
uniform float cooler_height = 2.3;
uniform float cooler_door = 0.78;
// The counter's middle x and its z range (front, back).
uniform vec3 counter = vec3(3.0, -1.15, -4.3);
// The cigarette rack: the wall's x and which way the room is (-1 / +1).
uniform vec2 rack = vec2(5.0, -1.0);
uniform vec4 gondola_x = vec4(0.0);
uniform int gondola_count = 0;
uniform vec3 gondola_zh = vec3(-2.6, -8.0, 1.55);
// Paint (sRGB as written; decoded here).
uniform vec3 wall_color = vec3(0.92, 0.92, 0.88);
uniform vec3 floor_color = vec3(0.86, 0.84, 0.78);
uniform vec3 shelf_color = vec3(0.86, 0.86, 0.84);
uniform float seed = 0.0;
// How bright the room reads through the glass by day and after dark (times lamp_factor).
uniform float energy_day = 0.55;
uniform float energy_night = 1.15;

global uniform float lamp_factor;

varying vec3 store_pos;
varying vec3 store_cam;

const int R_NONE = 0;
const int R_FLOOR = 1;
const int R_CEIL = 2;
const int R_WALL = 3;
const int R_BACK = 4;
const int R_GONDOLA = 5;
const int R_COOLER = 6;
const int R_COUNTER = 7;
const int R_RACK = 8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// CornerStoreKit.product_color(): every colour a shelf has, a little greyed.
vec3 product_color(float h) {
	vec3 c = 0.5 + 0.5 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
	c = mix(vec3(dot(c, vec3(0.333))), c, 0.75);
	float light = hash21(vec2(h * 91.0, 3.3));
	return c * mix(0.35, 0.95, light) + (light > 0.85 ? vec3(0.25) : vec3(0.0));
}

// A box lo..hi: updates the nearest hit (t, normal, id).
void hit_box(vec3 ro, vec3 rd, vec3 inv, vec3 lo, vec3 hi, int id, inout float best, inout vec3 bn, inout int bid) {
	vec3 t0 = (lo - ro) * inv;
	vec3 t1 = (hi - ro) * inv;
	vec3 tmn = min(t0, t1);
	vec3 tmx = max(t0, t1);
	float ta = max(max(tmn.x, tmn.y), max(tmn.z, 0.0));
	float tb = min(min(tmx.x, tmx.y), tmx.z);
	if (tb <= ta || ta >= best) {
		return;
	}
	best = ta;
	bn = ta == tmn.x ? vec3(-sign(rd.x), 0.0, 0.0) : (ta == tmn.y ? vec3(0.0, -sign(rd.y), 0.0) : vec3(0.0, 0.0, -sign(rd.z)));
	bid = id;
}

// Shelves of packs on a face (q: metres along, metres up), shelf every `pitch`.
vec3 shelf_face(vec2 q, float pitch, float k, float px) {
	float row = floor(q.y / pitch);
	float fy = fract(q.y / pitch);
	float pack_w = mix(0.07, 0.17, hash21(vec2(row, k)));
	float slot = floor(q.x / pack_w);
	float fx = fract(q.x / pack_w);
	float run = floor(slot / mix(2.0, 6.0, hash21(vec2(row, k * 1.7))));
	vec3 pack = product_color(hash21(vec2(run, row + k * 13.0)));
	float top = mix(0.55, 0.88, hash21(vec2(run, row * 7.0 + k)));
	float in_pack = step(0.08, fy) * step(fy, top) * step(0.08, fx) * step(fx, 0.94);
	float fine = 1.0 - smoothstep(0.01, 0.035, px);
	in_pack = mix(0.62, in_pack, fine);
	pack = mix(product_color(hash21(vec2(row, k))) * 0.8 + 0.08, pack, fine);
	vec3 c = mix(vec3(0.10, 0.10, 0.11), pack * (0.75 + 0.25 * fy / top), in_pack);
	return mix(c, vec3(0.75, 0.75, 0.72), step(fy, 0.06));
}

void vertex() {
	store_pos = (to_store * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_model = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	store_cam = (to_store * vec4(cam_model, 1.0)).xyz;
}

void fragment() {
	vec3 ro = store_pos;
	vec3 rd = normalize(store_pos - store_cam);
	vec3 col = vec3(0.0);
	float px = length(fwidth(store_pos));
	if (rd.z < -1e-4) {
		vec3 inv = 1.0 / mix(rd, sign(rd) * 1e-5 + vec3(1e-6), lessThan(abs(rd), vec3(1e-5)));
		float best = 1e8;
		vec3 bn = vec3(0.0, 0.0, 1.0);
		int bid = R_WALL;
		// The room's own planes.
		{
			float t = (room.z - ro.z) / rd.z;
			if (t > 0.0 && t < best) { best = t; bn = vec3(0.0, 0.0, 1.0); bid = R_WALL; }
		}
		if (abs(rd.x) > 1e-4) {
			float t = ((rd.x > 0.0 ? room.y : room.x) - ro.x) / rd.x;
			if (t > 0.0 && t < best) { best = t; bn = vec3(-sign(rd.x), 0.0, 0.0); bid = R_WALL; }
		}
		if (abs(rd.y) > 1e-4) {
			float t = ((rd.y > 0.0 ? ceiling : 0.0) - ro.y) / rd.y;
			if (t > 0.0 && t < best) { best = t; bn = vec3(0.0, -sign(rd.y), 0.0); bid = rd.y > 0.0 ? R_CEIL : R_FLOOR; }
		}
		// The fittings.
		hit_box(ro, rd, inv, vec3(room.x, 0.0, room.z), vec3(room.y, back_height, room.z + back_depth), R_BACK, best, bn, bid);
		hit_box(ro, rd, inv, vec3(min(cooler.x, cooler.y), 0.0, cooler.w), vec3(max(cooler.x, cooler.y), cooler_height, cooler.z), R_COOLER, best, bn, bid);
		hit_box(ro, rd, inv, vec3(counter.x - 0.31, 0.0, counter.z), vec3(counter.x + 0.31, 1.0, counter.y), R_COUNTER, best, bn, bid);
		hit_box(ro, rd, inv, vec3(min(rack.x, rack.x + rack.y * 0.3), 1.25, counter.z), vec3(max(rack.x, rack.x + rack.y * 0.3), 2.35, counter.y), R_RACK, best, bn, bid);
		for (int i = 0; i < 4; i++) {
			if (i < gondola_count) {
				float gx = gondola_x[i];
				hit_box(ro, rd, inv, vec3(gx - 0.45, 0.0, gondola_zh.y), vec3(gx + 0.45, gondola_zh.z, gondola_zh.x), R_GONDOLA, best, bn, bid);
			}
		}
		vec3 p = ro + rd * best;
		float pxh = px * (1.0 + best * 0.5);
		vec3 wall = cs_srgb_to_linear(wall_color);
		vec3 shelf = cs_srgb_to_linear(shelf_color);
		vec3 alb = wall;
		vec3 glow = vec3(0.0);
		if (bid == R_FLOOR) {
			vec2 t = floor(p.xz / 0.305);
			float chk = mod(t.x + t.y, 2.0);
			vec3 fl = cs_srgb_to_linear(floor_color);
			alb = mix(fl, fl * vec3(0.42, 0.44, 0.47), chk) * (0.93 + 0.1 * hash21(t));
			// The fittings' feet darken the floor round them a little.
			alb *= 0.85 + 0.15 * smoothstep(0.0, 1.5, min(abs(p.x - room.x), abs(p.x - room.y)));
		} else if (bid == R_CEIL) {
			alb = vec3(0.8);
			vec2 cell = vec2(fract((p.x - room.x) / 2.4), fract((p.z - room.z) / 2.4));
			float panel = step(0.25, cell.x) * step(cell.x, 0.75) * step(0.38, cell.y) * step(cell.y, 0.62);
			glow = vec3(1.0, 0.97, 0.91) * 3.2 * panel;
		} else if (bid == R_BACK) {
			if (bn.z > 0.5) {
				alb = shelf_face(vec2(p.x, p.y - 0.12), 0.38, seed + 1.0, pxh);
			} else {
				alb = shelf;
			}
		} else if (bid == R_GONDOLA) {
			if (abs(bn.x) > 0.5) {
				alb = shelf_face(vec2(p.z, p.y - 0.12), 0.38, seed + 3.0 + sign(bn.x), pxh);
			} else if (bn.z > 0.5) {
				alb = shelf_face(vec2(p.x, p.y - 0.12), 0.38, seed + 7.0, pxh);
			} else {
				alb = shelf;
			}
		} else if (bid == R_COOLER) {
			if (abs(bn.x) > 0.5 && p.y < 2.0) {
				// Glass doors on a lit cabinet of bottles: a mullion every door.
				float along = (cooler.z - p.z) / cooler_door;
				float f = fract(along);
				float mull = 1.0 - step(0.04, f) * step(f, 0.96);
				vec3 inside = shelf_face(vec2(p.z * 1.6, p.y - 0.15), 0.36, seed + 11.0, pxh) * 1.4;
				alb = mix(inside, vec3(0.55, 0.56, 0.58), mull);
				glow = mix(vec3(0.95, 0.98, 1.0) * 0.6 + inside * 0.9, vec3(1.2), mull * 0.3);
			} else if (abs(bn.x) > 0.5) {
				alb = vec3(0.04);
				glow = vec3(0.9, 0.95, 1.0) * 0.9;
			} else {
				alb = vec3(0.2, 0.2, 0.22);
			}
		} else if (bid == R_COUNTER) {
			alb = bn.y > 0.5 ? vec3(0.42, 0.40, 0.38) : vec3(0.28, 0.18, 0.12);
		} else if (bid == R_RACK) {
			if (abs(bn.x) > 0.5) {
				vec2 q = vec2(p.z / 0.058, (p.y - 1.25) / 0.11);
				vec2 cell = floor(q);
				vec3 pk = product_color(hash21(cell + seed));
				float gap = step(0.1, fract(q.x)) * step(0.15, fract(q.y));
				float fine = 1.0 - smoothstep(0.01, 0.03, pxh);
				alb = mix(vec3(0.12), mix(pk * 0.7, pk, gap), mix(0.7, 1.0, fine));
				if (p.y > 2.2) {
					glow = vec3(1.0, 0.95, 0.85) * 1.2;
				}
			} else {
				alb = vec3(0.12);
			}
		}
		// Lit from the ceiling: brighter up high, the floor a little shaded far in.
		float light = 0.78 + 0.22 * clamp(p.y / ceiling, 0.0, 1.0);
		light *= 1.0 - 0.18 * clamp((room.w - p.z) / max(room.w - room.z, 1.0), 0.0, 1.0);
		col = alb * light * vec3(1.0, 0.97, 0.92) + glow;
	}
	float energy = mix(energy_day, energy_night, clamp(lamp_factor, 0.0, 1.0));
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = cs_out(vec3(0.012, 0.014, 0.014));
	ROUGHNESS = 0.05;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	EMISSION = cs_out(col * energy * (1.0 - f));
}
