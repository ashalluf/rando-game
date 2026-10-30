shader_type spatial;
render_mode cull_back;

// The schools' buildings and fittings (Schools, SchoolKit) as ONE material: a chunk's classroom
// wings, office, gym, auditorium, portables, signs, flag, scoreboard and stadium lights are one mesh
// and one draw. Each face says what it is in COLOR.a (SchoolKit.K_*, in 32nds) and carries its
// paint in COLOR.rgb (display numbers); UV is metres in the face's frame (x along the face, y up
// from the foot), UV2.x the height of the face's top, UV2.y a parameter. On a wall (0 stucco,
// 1 brick, 7 siding) the parameter is the window layout: style + 16 x the number of whole bays,
// with UV.x zero at the first bay (SchoolKit.wall()).
//    0 stucco   1 brick   2 concrete   3 roof membrane   4 painted steel   5 glass (a lobby)
//    6 door (UV2.y its width)   7 T1-11 siding   8 sign cabinet   9 letters   10 LED board (UV2.y 1
//    a lit character)   11 primed mural wall   12 standing-seam metal   13 stadium lamp (UV2.y 1
//    dark: not a game night)   14 flag   15 scoreboard face   16 concrete block   17 painted trim
//   18 louvres
// Window styles: 1 classroom ribbons (street side), 2 classroom yard side (beside each door),
// 3 gym clerestory, 4 auditorium slots, 5 office storefront, 6 portable.
// Behind every window is a classroom, traced per pixel (interior mapping): its back wall with a
// whiteboard and the pin-up boards, side walls, a tiled floor with rows of desks, the acoustic
// ceiling with its fluorescent troffers, a blind pulled to its own height; lit by day, a few rooms
// still lit after dark. The glass mirrors the sky (emitted by Fresnel, like the city's glazing).
// Colours are worked in display (sRGB) numbers and handed over with to_lit().

uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planks_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// How bright a classroom reads through the glass by day, and the share of rooms still lit at night.
uniform float room_day = 0.42;
uniform float room_night_share = 0.12;
uniform float room_depth = 7.0;
uniform float reflect_energy = 0.55;

global uniform float lamp_factor;
global uniform float night_factor;
global uniform float road_wetness;
global uniform float wind_factor;
// sRGB numbers, raw on BOTH renderers (a colour global is never decoded; probed 2026-10-05): it
// is already a display colour here, so it never goes through disp() as the textures do.
global uniform vec4 sky_tint;

varying float kind;
varying vec3 world_n;
varying vec3 world_p;

#include "res://shaders/color_space.gdshaderinc"

vec3 disp(vec3 c) {
	return cs_linear_renderer() ? cs_linear_to_srgb(c) : c;
}

vec3 to_lit(vec3 c) {
	return cs_linear_renderer() ? cs_srgb_to_linear(c) : c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 1 on lines every `spacing` along v, `w` wide, box-filtered (faded to its average under a pixel).
float lines(float v, float spacing, float w) {
	float g = abs(fract(v / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(v), 0.0005);
	return clamp((0.5 * (w + fw) - g) / fw, 0.0, 1.0) * min(1.0, w / fw);
}

float box_in(vec2 p, vec2 lo, vec2 hi) {
	vec2 fw = max(fwidth(p), vec2(0.0005));
	vec2 a = clamp((p - lo) / fw + 0.5, 0.0, 1.0) * clamp((hi - p) / fw + 0.5, 0.0, 1.0);
	return a.x * a.y;
}

void vertex() {
	kind = floor(COLOR.a * 32.0);
	// The flag waves: a travelling ripple growing toward the fly end, faster in a wind.
	if (int(kind + 0.5) == 14) {
		float x = UV.x;
		float w = 0.6 + 1.2 * wind_factor;
		VERTEX += NORMAL * (sin(x * 3.1 - TIME * (2.4 + 2.0 * w)) * 0.09 + sin(x * 6.3 - TIME * 4.1 + UV.y * 2.0) * 0.03) * (x / 1.83) * w;
		VERTEX.y -= (1.0 - w * 0.5) * 0.18 * (x / 1.83) * (x / 1.83);
	}
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A classroom behind a pane, traced. `q` the point on the glass in the room's frame (x across the
// room from its left wall, y up from its floor), `rw` x `rh` the room, `d` the view ray in the
// wall's frame (z out of the wall), `id` the room. Returns the room's colour (display numbers) and
// in .a how lit it is (emitted).
vec4 classroom(vec2 q, float rw, float rh, vec3 d, vec2 id) {
	float h1 = hash12(id * 1.37 + 0.5);
	float h2 = hash12(id * 2.11 + 7.3);
	float depth = room_depth * (0.85 + 0.3 * h1);
	vec3 o = vec3(q, 0.0);
	vec3 dir = normalize(vec3(d.x, d.y, min(d.z, -0.02)));
	float tb = (-depth - o.z) / dir.z;
	float tx = dir.x > 0.0 ? (rw - o.x) / dir.x : (0.0 - o.x) / min(dir.x, -1e-4);
	float ty = dir.y > 0.0 ? (rh - o.y) / dir.y : (0.0 - o.y) / min(dir.y, -1e-4);
	float t = min(tb, min(tx, ty));
	vec3 hp = o + dir * t;
	vec3 wall_c = mix(vec3(0.86, 0.83, 0.74), vec3(0.80, 0.84, 0.82), step(0.6, h2));
	vec3 c;
	float glow = 0.0;
	// Desks: a plane at 0.74 m, between 1.4 m and the back, in rows.
	float td = dir.y < 0.0 ? (0.74 - o.y) / dir.y : 1e9;
	if (td > 0.0 && td < t) {
		vec3 dp = o + dir * td;
		vec2 g = vec2(dp.x, -dp.z);
		vec2 cell = vec2(fract(g.x / 1.25), fract(g.y / 1.1));
		if (g.y > 1.6 && g.y < depth - 1.2 && cell.x > 0.12 && cell.x < 0.62 && cell.y > 0.2 && cell.y < 0.72 && g.x > 0.4 && g.x < rw - 0.4) {
			return vec4(vec3(0.62, 0.52, 0.38) * (0.9 + 0.2 * hash12(floor(g / vec2(1.25, 1.1)))), 1.0);
		}
	}
	if (t == tb) {
		// The back wall: the whiteboard across the middle, cork boards, the clock.
		vec2 b = hp.xy;
		c = wall_c;
		float wb = box_in(b, vec2(rw * 0.2, 0.95), vec2(rw * 0.8, 2.1));
		c = mix(c, vec3(0.93, 0.94, 0.93), wb);
		float cork = box_in(b, vec2(0.4, 1.0), vec2(rw * 0.2 - 0.3, 2.0)) + box_in(b, vec2(rw * 0.8 + 0.3, 1.0), vec2(rw - 0.4, 2.0));
		vec3 pin = mix(vec3(0.62, 0.45, 0.30), vec3(0.85, 0.30 + 0.5 * h1, 0.25 + 0.6 * h2), step(0.5, hash12(floor(b * 3.0) + id)));
		c = mix(c, pin, clamp(cork, 0.0, 1.0));
		c = mix(c, vec3(0.15), box_in(b, vec2(rw * 0.5 - 0.15, 2.35), vec2(rw * 0.5 + 0.15, 2.65)));
	} else if (t == tx) {
		// A side wall: cubbies low down, posters.
		vec2 b = vec2(-hp.z, hp.y);
		c = wall_c * 0.95;
		float cub = box_in(b, vec2(0.6, 0.1), vec2(depth - 0.6, 1.0));
		vec2 cc = fract(b / vec2(0.4, 0.3));
		c = mix(c, mix(vec3(0.55, 0.42, 0.28), vec3(0.2 + 0.6 * hash12(floor(b / vec2(0.4, 0.3))), 0.3, 0.5), step(0.15, cc.x) * step(0.15, cc.y) * 0.6), cub);
		float poster = box_in(fract(b / vec2(2.3, 9.0)) * vec2(2.3, 9.0), vec2(0.8, 1.4), vec2(1.5, 2.3));
		c = mix(c, vec3(0.3 + 0.6 * h2, 0.5 + 0.4 * h1, 0.75), poster * step(1.0, b.x));
	} else if (dir.y > 0.0) {
		// The acoustic ceiling and its troffers.
		vec2 b = vec2(hp.x, -hp.z);
		c = vec3(0.90, 0.90, 0.87) * (1.0 - 0.25 * max(lines(b.x, 0.61, 0.02), lines(b.y, 1.22, 0.02)));
		vec2 tc = vec2(fract(b.x / 2.44), fract(b.y / 2.44));
		float troffer = step(0.3, tc.x) * step(tc.x, 0.55) * step(0.25, tc.y) * step(tc.y, 0.75);
		c = mix(c, vec3(1.0, 0.99, 0.95), troffer);
		glow = troffer;
	} else {
		// The floor: vinyl composition tile, a checker of two shades.
		vec2 b = vec2(hp.x, -hp.z);
		vec2 tl = floor(b / 0.305);
		c = mix(vec3(0.72, 0.70, 0.64), vec3(0.62, 0.60, 0.55), step(0.5, hash12(tl))) * (1.0 - 0.15 * max(lines(b.x, 0.305, 0.004), lines(b.y, 0.305, 0.004)));
	}
	// Darker toward the back and the floor, as a room is.
	float fall = mix(1.0, 0.62, clamp(-hp.z / depth, 0.0, 1.0));
	return vec4(c * fall, 1.0 + glow);
}

// One window cell: frame and mullions, the pane's room, a blind, the sky in the glass.
void window(vec2 q, vec2 size, float mull, vec2 id, vec3 vd_w, vec3 n, vec3 t, inout vec3 albedo, inout vec3 emit, inout float rough, inout float metal, float room_h) {
	float frame = 0.06;
	vec2 inner = q - vec2(frame);
	vec2 isz = size - vec2(frame * 2.0);
	vec3 alu = vec3(0.72, 0.73, 0.74);
	float in_pane = box_in(q, vec2(frame), size - vec2(frame));
	float m = mull > 0.0 ? lines(inner.x, mull, 0.05) * step(0.2, inner.x) * step(inner.x, isz.x - 0.2) : 0.0;
	// A transom bar across the upper third.
	m = max(m, lines(inner.y - isz.y * 0.68, 1000.0, 0.05));
	float glass = in_pane * (1.0 - m);
	// The view ray in the wall's frame (z out of the wall).
	vec3 dirw = -vd_w;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 d = vec3(dot(dirw, t), dot(dirw, up), dot(dirw, n));
	float rh = 3.5;
	vec2 rq = vec2(q.x + (room_h - size.x) * 0.5, q.y + 1.0);
	vec4 room = classroom(rq, room_h, rh, d, id);
	float h = hash12(id + 3.1);
	// Lit by day (the lights on, the daylight in); after dark only a few rooms.
	float lit_night = step(1.0 - room_night_share, hash12(id * 0.71 + 9.0));
	float light = room_day * (1.0 - night_factor) * (0.75 + 0.5 * step(0.3, h)) + lamp_factor * lit_night * 0.85;
	vec3 inside = room.rgb * light + room.rgb * (room.a - 1.0) * (0.35 * (1.0 - night_factor) + lit_night * lamp_factor);
	// A blind pulled to its own height.
	float blind = mix(0.0, 0.75, hash12(id * 1.9 + 4.4)) * step(0.35, hash12(id * 0.37));
	float under_blind = step(q.y, size.y - blind * size.y);
	vec3 slat = vec3(0.84, 0.80, 0.70) * (0.85 + 0.15 * lines(q.y, 0.025, 0.006)) * (0.25 + 0.75 * (light + 0.2));
	inside = mix(slat, inside, under_blind);
	float fres = pow(1.0 - clamp(dot(vd_w, n), 0.0, 1.0), 4.0);
	vec3 sky = sky_tint.rgb;
	vec3 refl = sky * (0.08 + 0.85 * fres) * reflect_energy;
	albedo = mix(albedo, alu, max(in_pane * m, (1.0 - in_pane) * box_in(q, vec2(0.0), size)));
	albedo = mix(albedo, vec3(0.02, 0.025, 0.03), glass);
	emit += (inside * 0.9 + refl) * glass;
	rough = mix(rough, 0.05, glass);
	metal = mix(metal, 0.6, max(in_pane * m, (1.0 - in_pane) * box_in(q, vec2(0.0), size)) * 0.6);
}

void fragment() {
	vec2 uv = UV;
	float top_y = max(UV2.x, 0.01);
	float param = UV2.y;
	bool top = world_n.y > 0.5;
	vec3 paint = COLOR.rgb;
	vec3 albedo = paint;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float glow = 0.0;
	int k = int(kind + 0.5);
	float foot = 1.0 - smoothstep(0.0, 0.4, uv.y);
	vec3 vd_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	if (k == 0 || k == 1 || k == 7 || k == 11) {
		if (k == 0 || k == 11) {
			// Stucco: a sand finish (the mural wall a smooth primer), dirt down from the top.
			vec3 tx = disp(texture(concrete_tex, uv / 3.5).rgb);
			float l = dot(tx, vec3(0.33)) / 0.55;
			albedo = paint * mix(0.9, 1.06, clamp(l - 0.3, 0.0, 1.0)) * (0.96 + 0.06 * vnoise(uv * 0.6));
			if (k == 11) {
				albedo = paint * (0.97 + 0.03 * vnoise(uv * 1.3));
				rough = 0.7;
			} else {
				rough = 0.92;
			}
		} else if (k == 1) {
			// Brick: the photographed texture tinted to the school's brick, joints shaded.
			vec3 tx = disp(texture(brick_tex, uv / vec2(1.6, 1.2)).rgb);
			float l = dot(tx, vec3(0.33)) / 0.45;
			albedo = paint * mix(0.75, 1.2, clamp(l - 0.2, 0.0, 1.0));
			// The mesh has no tangents (a NORMAL_MAP would do nothing): the relief is shaded in.
			float relief = texture(brick_nrm, uv / vec2(1.6, 1.2)).g;
			albedo *= 0.85 + 0.3 * relief;
			rough = 0.9;
		} else {
			// T1-11 siding: grooves every 20 cm, the plywood's grain under the paint.
			vec3 tx = disp(texture(planks_tex, uv * vec2(0.3, 0.08)).rgb);
			albedo = paint * (0.9 + 0.15 * dot(tx, vec3(0.33))) * (1.0 - 0.35 * lines(uv.x, 0.203, 0.012));
			rough = 0.8;
		}
		albedo *= 1.0 - 0.1 * foot - 0.07 * smoothstep(0.55, 1.0, vnoise(vec2(uv.x * 1.1, 0.5))) * smoothstep(top_y - 1.5, top_y, uv.y);
		int style = int(mod(param, 16.0) + 0.5);
		float bays = floor(param / 16.0);
		if (!top && abs(world_n.y) < 0.5 && style > 0 && bays > 0.5) {
			vec3 n = normalize(world_n);
			vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));
			float pitch = style == 3 ? 6.0 : (style == 4 ? 7.0 : (style >= 5 ? 4.0 : 9.0));
			if (uv.x > 0.0 && uv.x < bays * pitch) {
				float bx = mod(uv.x, pitch);
				float bi = floor(uv.x / pitch);
				vec2 seed = floor(world_p.xz * 0.05) + vec2(bi, 0.0);
				if (style == 1 || style == 2) {
					float storey = 4.0;
					float fl = floor(uv.y / storey);
					float y = uv.y - fl * storey;
					vec2 lo = style == 1 ? vec2(0.5, 1.0) : vec2(3.0, 1.2);
					vec2 hi = style == 1 ? vec2(8.5, 3.0) : vec2(8.4, 3.0);
					if (uv.y < top_y - 0.6 && bx > lo.x && bx < hi.x && y > lo.y && y < hi.y) {
						window(vec2(bx, y) - lo, hi - lo, style == 1 ? 2.0 : 1.8, seed + vec2(0.0, fl * 7.0), vd_w, n, t, albedo, emit, rough, metal, pitch - 0.4);
					}
					// A sill under each ribbon.
					albedo *= 1.0 - 0.25 * box_in(vec2(bx, y), vec2(lo.x - 0.1, lo.y - 0.12), vec2(hi.x + 0.1, lo.y - 0.02));
				} else if (style == 3) {
					vec2 lo = vec2(0.6, top_y - 4.0);
					vec2 hi = vec2(5.4, top_y - 1.8);
					if (bx > lo.x && bx < hi.x && uv.y > lo.y && uv.y < hi.y) {
						window(vec2(bx, uv.y) - lo, hi - lo, 1.2, seed, vd_w, n, t, albedo, emit, rough, metal, 6.0);
					}
					// Piers between the bays.
					albedo *= 1.0 - 0.12 * box_in(vec2(bx, uv.y), vec2(-0.1, 0.0), vec2(0.35, top_y));
				} else if (style == 4) {
					vec2 lo = vec2(3.05, 1.2);
					vec2 hi = vec2(3.95, top_y - 1.6);
					if (bx > lo.x && bx < hi.x && uv.y > lo.y && uv.y < hi.y) {
						window(vec2(bx, uv.y) - lo, hi - lo, 0.0, seed, vd_w, n, t, albedo, emit, rough, metal, 4.0);
					}
					// Fins of the wall's own finish either side of the slot.
					albedo *= 1.0 - 0.15 * (box_in(vec2(bx, uv.y), vec2(2.6, 0.0), vec2(2.9, top_y)) + box_in(vec2(bx, uv.y), vec2(4.1, 0.0), vec2(4.4, top_y)));
				} else if (style == 5) {
					vec2 lo = vec2(0.12, 0.35);
					vec2 hi = vec2(3.88, 3.1);
					if (bx > lo.x && bx < hi.x && uv.y > lo.y && uv.y < hi.y) {
						window(vec2(bx, uv.y) - lo, hi - lo, 0.0, seed, vd_w, n, t, albedo, emit, rough, metal, 4.0);
					}
				} else if (style == 6) {
					vec2 lo = vec2(1.3, 1.05);
					vec2 hi = vec2(2.7, 2.05);
					if (bx > lo.x && bx < hi.x && uv.y > lo.y && uv.y < hi.y) {
						window(vec2(bx, uv.y) - lo, hi - lo, 0.7, seed, vd_w, n, t, albedo, emit, rough, metal, 3.0);
					}
					albedo *= 1.0 - 0.3 * (1.0 - box_in(vec2(bx, uv.y), lo - vec2(0.08), hi + vec2(0.08))) * box_in(vec2(bx, uv.y), lo - vec2(0.14), hi + vec2(0.14));
				}
			}
		}
	} else if (k == 2 || k == 16) {
		vec3 tx = disp(texture(concrete_tex, uv / 4.0).rgb);
		albedo = paint * (0.85 + 0.25 * dot(tx, vec3(0.33)));
		if (k == 16) {
			vec2 b = uv / vec2(0.40, 0.20);
			b.x += floor(b.y) * 0.5;
			albedo *= (0.92 + 0.12 * hash12(floor(b))) * (1.0 - 0.25 * max(lines(b.x * 0.40, 0.40, 0.01), lines(uv.y, 0.20, 0.01)));
		}
		rough = 0.9;
	} else if (k == 3) {
		// The membrane: welded seams, ponding stains.
		albedo = paint * (0.94 + 0.08 * vnoise(world_p.xz * 0.3)) * (1.0 - 0.06 * lines(world_p.x, 1.8, 0.04));
		albedo *= 1.0 - 0.12 * smoothstep(0.65, 0.85, vnoise(world_p.xz * 0.12));
		rough = 0.75;
	} else if (k == 4 || k == 17) {
		albedo = paint * (0.94 + 0.08 * vnoise(uv * 3.0));
		rough = k == 4 ? 0.5 : 0.55;
		metal = k == 4 ? 0.3 : 0.0;
	} else if (k == 5) {
		// A glazed lobby: mullions every 1.5 m, a lit interior behind.
		float fres = pow(1.0 - clamp(dot(vd_w, normalize(world_n)), 0.0, 1.0), 4.0);
		float mul = max(lines(uv.x, 1.5, 0.06), lines(uv.y, 2.6, 0.08));
		vec3 inside = vec3(0.70, 0.66, 0.58) * (0.18 * (1.0 - night_factor) + 0.6 * lamp_factor) * (0.8 + 0.2 * vnoise(uv * 0.5));
		albedo = mix(vec3(0.03), vec3(0.6, 0.62, 0.64), mul);
		emit = (inside + sky_tint.rgb * (0.1 + 0.8 * fres) * reflect_energy) * (1.0 - mul);
		rough = mix(0.05, 0.4, mul);
		metal = mul * 0.6;
	} else if (k == 6) {
		// A door: painted steel, a narrow vision panel, the push bar, a kick plate.
		float w = max(param, 0.5);
		albedo = paint * (0.92 + 0.08 * vnoise(uv * 4.0));
		float panel = box_in(uv, vec2(w * 0.62, 1.25), vec2(w * 0.86, 1.95));
		albedo = mix(albedo, vec3(0.04, 0.05, 0.06), panel);
		emit += sky_tint.rgb * 0.2 * panel;
		albedo = mix(albedo, vec3(0.75, 0.76, 0.77), box_in(uv, vec2(0.08, 0.98), vec2(w - 0.08, 1.06)));
		albedo = mix(albedo, vec3(0.62, 0.63, 0.64), box_in(uv, vec2(0.04, 0.0), vec2(w - 0.04, 0.25)));
		rough = mix(0.45, 0.1, panel);
		metal = 0.2;
	} else if (k == 8) {
		albedo = paint * (0.95 + 0.05 * vnoise(uv * 2.0));
		rough = 0.4;
		// The cabinet glows a little from inside after dark.
		emit = paint * 0.25 * lamp_factor;
	} else if (k == 9) {
		albedo = paint;
		rough = 0.45;
		emit = paint * 0.35 * lamp_factor * step(0.5, param);
	} else if (k == 10) {
		// LED matrix: a pitch of 25 mm; lit characters in their colour, the rest dark dots.
		vec2 dots = abs(fract(world_p.xy * 40.0 + world_p.zz * 40.0) - 0.5);
		float dot_m = 1.0 - smoothstep(0.25, 0.4, max(dots.x, dots.y));
		float fine = 1.0 - smoothstep(0.006, 0.02, fwidth(world_p.x + world_p.z));
		if (param > 0.5) {
			albedo = vec3(0.08);
			emit = paint * mix(0.7, 0.4 + 0.9 * dot_m, fine) * (0.8 + 1.6 * lamp_factor);
			rough = 0.3;
		} else {
			albedo = vec3(0.03) + vec3(0.04) * dot_m * fine;
			rough = 0.35;
		}
	} else if (k == 12) {
		// Standing-seam metal: a seam every 45 cm across, a light chalky finish.
		float seam = lines(uv.x, 0.45, 0.035);
		albedo = paint * (1.0 - 0.15 * seam) * (0.94 + 0.08 * vnoise(uv * vec2(0.5, 2.0)));
		metal = 0.5;
		rough = 0.42;
	} else if (k == 13) {
		albedo = vec3(0.78, 0.80, 0.80);
		emit = vec3(1.0, 0.97, 0.92);
		glow = param > 0.5 ? 0.0 : lamp_factor * 9.0;
		emit *= param > 0.5 ? 0.0 : 1.0;
		rough = 0.2;
	} else if (k == 14) {
		// The flag: thirteen stripes, the canton of stars (a dot grid), cloth shading.
		vec2 f = vec2(uv.x / 1.83, uv.y / 0.96);
		float stripe = mod(floor((1.0 - f.y) * 13.0), 2.0);
		vec3 c = mix(vec3(0.70, 0.08, 0.12), vec3(0.95, 0.95, 0.93), stripe);
		bool canton = f.x < 0.4 && f.y > 1.0 - 7.0 / 13.0;
		if (canton) {
			vec2 s = vec2(f.x / 0.4 * 6.0, (f.y - (1.0 - 7.0 / 13.0)) / (7.0 / 13.0) * 5.0);
			float star = 1.0 - smoothstep(0.16, 0.24, length(fract(s) - 0.5));
			c = mix(vec3(0.12, 0.16, 0.38), vec3(0.95), star * (1.0 - smoothstep(0.01, 0.03, fwidth(f.x))));
		}
		albedo = c * (0.85 + 0.15 * vnoise(uv * 4.0));
		rough = 0.85;
	} else if (k == 15) {
		albedo = vec3(0.04);
		rough = 0.6;
	} else if (k == 18) {
		albedo = paint * (1.0 - 0.6 * lines(uv.y, 0.06, 0.02));
		rough = 0.6;
		metal = 0.3;
	}
	albedo *= 1.0 - 0.2 * road_wetness * (top ? 1.0 : 0.4);
	ALBEDO = to_lit(clamp(albedo, vec3(0.0), vec3(1.0)));
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = to_lit(clamp(emit, vec3(0.0), vec3(1.0))) * (1.0 + glow);
}
