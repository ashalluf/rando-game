shader_type spatial;

// Worn asphalt. The road fills the bottom third of nearly every screenshot, and a single tiled
// texture reads as a flat grey plane however good the lighting is. This layers the things that
// actually make tarmac look used, all generated from world position so they tile seamlessly
// across chunks and never repeat visibly:
//   - slow mottling, so the surface is never one tone
//   - resurfacing patches on a jittered grid, each a slightly different colour and smoothness,
//     with a darker seam around the edge
//   - cracks, as thin dark ridges from folded noise
//   - oil and tyre staining in sparse blotches
// Wetness comes from the `road_wetness` global that Weather drives: wet tarmac is darker and
// much smoother, which is what makes rain read. After the rain (`road_drying`, see
// wet_drying.gdshaderinc) it dries the way a real street does: wheel tracks and pavements first,
// the crown before the kerbs, puddles shrinking from their edges, the gutters last, with a thin
// band of running water along each kerb for as long as the street is wet.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.72, 0.72, 0.74);
// Metres per texture tile.
uniform float tex_scale = 8.0;
uniform float seed = 0.0;
// Size of a resurfacing patch (metres) and how much of the road is patched.
uniform float patch_size = 7.0;
uniform float patch_amount = 0.30;
uniform float crack_amount = 0.5;
uniform float stain_amount = 0.32;
uniform float normal_depth = 0.75;
// Spacing of expansion joints in metres (0 = none). Pavements are poured in slabs; the grid of
// joints between them is the single most recognisable thing about a concrete sidewalk.
uniform float joint_spacing = 0.0;
uniform float joint_depth = 0.26;
// After the rain: metres of running water along each kerb, how fast it runs (m/s) and how
// rippled it is (normal depth), how much sooner the wheel tracks dry, how much longer the kerb
// side of the camber holds water than the crown, and how much sooner a pavement
// (joint_spacing > 0) drains than the carriageway.
uniform float gutter_width = 0.55;
uniform float gutter_flow = 0.35;
uniform float gutter_ripple = 0.4;
uniform float track_dry = 0.35;
uniform float camber_hold = 0.25;
uniform float pavement_drain = 0.2;
// Raindrops in standing water (puddles and the gutter run) while it rains: rings per square
// metre-ish cell, how many rings a cell throws a second, and how hard they bend the mirror.
uniform float ripple_scale = 2.6;
uniform float ripple_rate = 1.3;
uniform float ripple_strength = 0.55;
// The night city mirrored in the water (see the end of fragment()): its strength in standing
// water, how much of it the wet film carries as streaks, and the distance (m) it fades out by.
// Forward+ adds its screen-space reflections on top, so it runs at `mirror_forward` there.
uniform float mirror_night = 1.1;
uniform float mirror_film = 0.35;
uniform float mirror_fade = 70.0;
uniform float mirror_forward = 0.5;
// CityPlan.PARKING_LANE: the wheel tracks run in the travel lanes inside it.
const float CITY_PARKING_LANE = 2.6;

global uniform float road_wetness;
// How hard it is raining right now (Weather.rain_level, 0..1): drops ring the puddles.
global uniform float rain_intensity;
// 0 turns off the second texture fetch that breaks up the tiling. Quality clears it on the web
// and at the low levels, where roads fill the screen and every fetch counts.
global uniform float ground_detail;

varying vec3 world_pos;
varying vec2 plan_pos;
varying vec2 slab_uv;

#include "res://shaders/street_glow.gdshaderinc"
// Which way this road's lamps run (CityChunk._road_look): 0 no glow, 1 along Z, 2 along X. Seen
// from past `street_glow_near` metres the road wears the same lamp glow the far chunks do
// (far_ground.gdshader); closer in, the real lamps and their light pools take over.
uniform int lamp_axis = 0;
uniform float street_glow_near = 90.0;
uniform float street_glow_far = 200.0;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 hash22(vec2 p) {
	return vec2(hash12(p), hash12(p + 71.3));
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}


#include "res://shaders/wet_drying.gdshaderinc"


// Raindrop rings on standing water, as a tangent-space slope (xy). Three offset layers of cells,
// each cell dropping one ring at a time from its own jittered point at its own phase, so the
// rings never line up into a grid. A ring is a single damped wave front travelling outward.
vec2 rain_ripples(vec2 w, float t) {
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 p = w * ripple_scale + vec2(fi * 0.37, fi * 0.71);
		vec2 cell = floor(p);
		float h = hash12(cell + fi * 13.1);
		vec2 centre = 0.5 + (hash22(cell + fi * 5.3) - 0.5) * 0.5;
		float phase = fract(t * ripple_rate * (0.8 + 0.4 * h) + h * 7.0);
		vec2 d = fract(p) - centre;
		float r = length(d);
		float front = phase * 0.42;
		float x = (r - front) * 38.0;
		float wave = sin(x) * exp(-x * x * 0.08) * (1.0 - phase) * (1.0 - phase);
		slope += d / max(r, 1.0e-3) * wave;
	}
	return slope;
}


// The street canyon a puddle mirrors at night, looked up by the reflected ray `r`: building
// fronts a few degrees of heading wide, each lit shop by shop along its foot and window by window
// above, the roofline, then the dark sky. `sharp` 0 is the wet film's version: only the heading
// counts, so each light becomes a streak running toward the viewer, the way lights smear down a
// wet road.
vec3 mirrored_city(vec3 r, float sharp) {
	float e = r.y;
	float heading = atan(r.x, r.z) * 0.159155;
	float slot_f = heading * 90.0;
	float slot = floor(slot_f);
	float roof = mix(0.30, 1.0, hash12(vec2(slot, 3.7)));
	// Shops: a lit band along the foot of the facades, broken shop by shop, most of them warm.
	float shop_on = step(0.35, hash12(vec2(slot, 11.3)));
	vec3 shop_col = mix(vec3(1.0, 0.66, 0.36), vec3(0.72, 0.84, 1.0), step(0.78, hash12(vec2(slot, 17.9))));
	float shop_edge = smoothstep(0.02, 0.2, fract(slot_f)) * smoothstep(0.98, 0.8, fract(slot_f));
	// Offices above: floors by elevation, bays by heading, a third of them lit.
	float rows_f = e * 36.0;
	float bays_f = slot_f * 4.0;
	vec2 cell = floor(vec2(bays_f, rows_f));
	float lit = step(0.66, hash12(cell + vec2(slot * 0.37, 5.0)));
	float pane = smoothstep(0.3, 0.4, fract(rows_f)) * smoothstep(0.2, 0.3, fract(bays_f)) * smoothstep(0.95, 0.85, fract(bays_f));
	float fine = 1.0 - smoothstep(0.35, 0.9, max(fwidth(rows_f), fwidth(bays_f)));
	float windows = mix(0.1, lit * pane, fine * sharp);
	float facade = 1.0 - smoothstep(roof - 0.01, roof + 0.01, e);
	float band = 1.0 - smoothstep(0.035, 0.07, e);
	vec3 sharp_city = shop_col * (band * shop_on * shop_edge * 1.4) + vec3(1.0, 0.8, 0.55) * (windows * facade * (1.0 - band) * 0.7);
	// Smeared: only the brighter shop fronts streak, each at its own strength, brightest near
	// the horizon. Every front streaking alike combed the whole street with even stripes.
	float streak_k = shop_on * pow(hash12(vec2(slot, 23.1)), 3.0);
	vec3 streak = shop_col * streak_k * shop_edge * (1.0 - smoothstep(0.0, 0.3, e));
	// No early return for rays below the horizon: the fwidth() above needs every pixel of a quad.
	return mix(streak, sharp_city, sharp) * step(-0.02, e);
}


// Fades the mirrored city out with distance: far off, the real lamps' glow takes over, and a
// window grid squeezed into a few pixels only shimmers.
float near_mirror(float dist) {
	float k = 1.0 - smoothstep(mirror_fade * 0.5, mirror_fade, dist);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return k;
#else
	return k * mirror_forward;
#endif
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// City ground is laid out in plan coordinates in its chunk, so object space does not move
	// when the origin is re-centred (only the lamp pattern reads it).
	plan_pos = VERTEX.xz;
	slab_uv = UV;
}


void fragment() {
	// Kerb faces, seat walls, steps and slab edges wear the same material as the ground on top,
	// and mapped from above a vertical face drew every texel as a streak down its whole height
	// (the Esplanade walkway's seat wall was a band of vertical smears). A face steeper than
	// 60 degrees is mapped side-on instead - along the face and down it - and holds no water.
	// The face's own normal from the screen derivatives, not the mesh's: meshes built with a
	// shared smooth group (the replica's walkway) average a wall's normals with the ground on top
	// of it, and read by those a seat wall never counted as a wall.
	vec3 wn = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	float side = step(abs(wn.y), 0.5);
	vec2 along = normalize(vec2(-wn.z, wn.x) + vec2(1.0e-4, 0.0));
	vec2 w = mix(world_pos.xz, vec2(dot(world_pos.xz, along), -world_pos.y), side);
	vec2 uv = w / tex_scale;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	float rough = texture(rough_tex, uv).r;

	// Kill the visible repeat. Across a plaza or a long pavement the eye picks the tile grid
	// out immediately, and no amount of wear on top hides it. Sample the same texture a second
	// time, rotated and at a different scale, and cross-fade between the two on slow noise:
	// one extra fetch, and the grid stops existing.
	if (ground_detail > 0.5) {
		vec2 uv2 = (mat2(vec2(0.80, -0.60), vec2(0.60, 0.80)) * w) / (tex_scale * 1.37) + vec2(13.7, 4.1);
		float variant = smoothstep(0.34, 0.66, fbm(w * 0.019 + 91.0 + seed));
		base = mix(base, texture(albedo_tex, uv2).rgb * tint, variant);
	}

	// Slow mottling: patches of the road that have aged differently.
	float mottle = fbm(w * 0.045 + seed);
	base *= 0.82 + 0.36 * mottle;

	// Resurfacing patches on a jittered grid. Each patch has its own tone and smoothness, and a
	// darker seam where the new asphalt meets the old.
	vec2 cell = floor(w / patch_size);
	vec2 jitter = (hash22(cell + seed) - 0.5) * 0.55;
	vec2 local = fract(w / patch_size) - 0.5 - jitter;
	float patch_roll = hash12(cell * 1.7 + seed);
	if (patch_roll < patch_amount) {
		float half_w = 0.30 + 0.16 * hash12(cell + 5.1);
		float half_h = 0.30 + 0.16 * hash12(cell + 9.7);
		float inside = step(abs(local.x), half_w) * step(abs(local.y), half_h);
		float edge = max(abs(local.x) / half_w, abs(local.y) / half_h);
		float seam = inside * smoothstep(0.78, 1.0, edge);
		float shade = 0.84 + 0.26 * hash12(cell + 13.3);
		base = mix(base, base * shade, inside * 0.5);
		base *= 1.0 - 0.28 * seam;
		rough = mix(rough, rough * (0.7 + 0.5 * hash12(cell + 3.3)), inside);
	}

	// Cracks: fold the noise so it ridges, then keep only the sharpest lines. The frequency is
	// what decides whether this reads as a crack or as a dried-mud pattern: at 0.75 the lines
	// wandered over several metres and were a hand's width across.
	float ridge = 1.0 - abs(fbm(w * 1.7 + 17.0 + seed) * 2.0 - 1.0);
	float crack = smoothstep(0.955, 0.999, ridge) * crack_amount;
	base *= 1.0 - 0.34 * crack;
	rough = mix(rough, 1.0, crack * 0.6);

	// Oil and rubber: sparse dark blotches, smoother than the surrounding tarmac. Same trap as
	// the cracks - at a low frequency these became metres-long tendrils crawling down the
	// carriageway, which is the first thing the eye picks out as wrong.
	float stain = smoothstep(0.82, 0.98, fbm(w * 1.15 + 41.0 + seed)) * stain_amount;
	base *= 1.0 - 0.15 * stain;
	rough = mix(rough, 0.45, stain * 0.5);

	// Expansion joints, with each slab cast at a slightly different shade.
	if (joint_spacing > 0.01) {
		vec2 slab = w / joint_spacing;
		vec2 edge = abs(fract(slab) - 0.5);
		// edge is 0 at a slab's centre and 0.5 at its joint, so this has to RISE toward 0.5.
		// It used to be smoothstep(0.5, 0.5 - 0.025, ...) - edge0 above edge1, a decreasing
		// ramp - which made `line` 1 over about 95 % of every slab and 0 on the joint. Every
		// pavement, plaza, car park and port yard in the city was therefore multiplied by
		// 1 - joint_depth across its whole face and wore a BRIGHT grid where the joints should
		// be, which is most of why the ground read as a dark sheet from the air.
		float line = smoothstep(0.5 - 0.025, 0.5, max(edge.x, edge.y));
		base *= mix(1.0, 1.0 - joint_depth, line);
		rough = mix(rough, 1.0, line * 0.5);
		base *= 0.965 + 0.07 * hash12(floor(slab) + seed);
	}

	// Wet tarmac goes darker and far glossier, and water stands in the low spots. The puddles
	// are what make a rainy street at night read: mirror-flat, they hold the lit windows and
	// the lamps, where evenly glossy tarmac only ever gives a smeared sheen. They spread as the
	// street soaks, and pavements, which drain, get fewer.
	// While it rains `film` and `damp` are both the global wetness, exactly as before; the
	// uneven drying and the gutter water only run with `ground_detail` (off on the web and the
	// low levels, which keep the even look) and nothing here runs on a dry street.
	float wet = clamp(road_wetness, 0.0, 1.0);
	float film = wet;
	float damp = wet;
	float puddle = 0.0;
	float gutter = 0.0;
	vec3 flow_normal = vec3(0.5, 0.5, 1.0);
	if (wet > 0.01) {
		float pn = fbm(w * 0.075 + 57.0 + seed) + 0.25 * value_noise(w * 0.9 + 3.0);
		// How much water the puddles hold: all of it while it rains; drying, they outlast the
		// tarmac round them and shrink from their edges (the cover threshold below rises).
		float pw = wet;
		if (ground_detail > 0.5) {
			float drying = clamp(road_drying, 0.0, 1.0);
			// Only drying spreads the water unevenly; while it rains nothing reads `hold`.
			float hold = 1.0;
			if (drying > 0.0) {
				// The puddle field is the street's low spots: the lower, the longer it stays
				// wet, so each shrinking puddle keeps a damp dark rim.
				hold = max(wet_hold_noise(w), smoothstep(0.5, 0.75, pn));
			}
			if (lamp_axis > 0) {
				// Where the kerbs and lanes are. The slab's UV runs 0..1 across its rect, so its
				// size in metres is the ratio of the plan position's screen derivatives to the
				// UV's (exact: both are linear over the slab). Only a street slab - long, and a
				// street's width - has kerbs down its sides; a junction square, a skirt (constant
				// UV) or a short replica piece falls through to the noise alone.
				float across_p = lamp_axis == 1 ? plan_pos.x : plan_pos.y;
				float along_p = lamp_axis == 1 ? plan_pos.y : plan_pos.x;
				float across_uv = lamp_axis == 1 ? slab_uv.x : slab_uv.y;
				float along_uv = lamp_axis == 1 ? slab_uv.y : slab_uv.x;
				float width = length(vec2(dFdx(across_p), dFdy(across_p))) / max(length(vec2(dFdx(across_uv), dFdy(across_uv))), 1.0e-7);
				float run = length(vec2(dFdx(along_p), dFdy(along_p))) / max(length(vec2(dFdx(along_uv), dFdy(along_uv))), 1.0e-7);
				// Running water: the asphalt's own normal map stretched down the gutter and slid
				// along it, which reads as the rippled film of a kerb-side run-off.
				float flow_dir = hash12(vec2(seed, 5.0)) < 0.5 ? -1.0 : 1.0;
				float slide = flow_dir * TIME * gutter_flow;
				vec2 fuv = lamp_axis == 1 ? vec2(w.x / 0.7, (w.y + slide) / 2.6) : vec2((w.x + slide) / 2.6, w.y / 0.7);
				// Derivatives here, in uniform control flow, so the fetch itself can wait until a
				// pixel is known to be in the gutter (most of the road never needs it).
				vec2 fuv_dx = dFdx(fuv);
				vec2 fuv_dy = dFdy(fuv);
				if (width > 5.0 && width < 60.0 && run > 1.8 * width) {
					float a = clamp(across_uv, 0.0, 1.0) * width;
					float half_w = width * 0.5;
					float from_centre = abs(a - half_w);
					float kerb = half_w - from_centre;
					// The camber sheds water from the crown toward the kerbs.
					hold += camber_hold * smoothstep(0.3, 1.0, from_centre / half_w);
					// Two wheel tracks down each travel lane (the lanes CityPlan.lane_center()
					// lays out: one a side on a street, two on an avenue). A lane's pair wanders
					// together, and shows only in stretches - evenly down the whole road it read
					// as a row of painted stripes.
					float lanes = width > 15.0 ? 2.0 : 1.0;
					float travel = half_w - CITY_PARKING_LANE - 0.2;
					if (from_centre < travel) {
						float lane_w = travel / lanes;
						float lane_id = floor(from_centre / lane_w) + (a > half_w ? 7.0 : 0.0);
						float wander = 0.45 * (value_noise(vec2(along_p * 0.03, lane_id * 3.1 + seed)) - 0.5);
						float worn = smoothstep(0.3, 0.75, value_noise(vec2(along_p * 0.06 + 11.0, lane_id * 5.7 + seed)));
						float o = (fract(from_centre / lane_w) - 0.5) * lane_w + wander;
						float track = (1.0 - smoothstep(0.08, 0.5, abs(abs(o) - 0.8))) * worn;
						hold -= track_dry * track;
					}
					// The gutter: a ragged band of running water at the kerb, the last to dry.
					// Past 3.5 of its widest it adds nothing, so the rest of the road skips it.
					if (kerb < gutter_width * 1.35 * 3.5) {
						float gw = gutter_width * (0.65 + 0.7 * value_noise(vec2(along_p * 0.4, a + seed)));
						gutter = 1.0 - smoothstep(gw * 0.55, gw, kerb);
						hold = max(hold, 1.0 - smoothstep(gw, gw * 3.5, kerb));
						if (gutter > 0.0) {
							flow_normal = textureGrad(normal_tex, fuv, fuv_dx, fuv_dy).rgb;
						}
					}
				}
			}
			if (joint_spacing > 0.01) {
				// Pavements drain, and each slab dries at its own pace.
				hold = hold * 0.8 - pavement_drain + 0.3 * (hash12(floor(w / joint_spacing) + seed + 7.0) - 0.5);
			}
			vec2 fd = wet_film_damp(wet, hold);
			film = fd.x;
			damp = fd.y;
			pw = mix(wet, sqrt(wet) * smoothstep(0.01, 0.1, wet), drying);
			gutter *= smoothstep(0.03, 0.2, wet);
		}
		float cover = mix(0.80, 0.52, pw) + (joint_spacing > 0.01 ? 0.08 : 0.0);
		puddle = smoothstep(cover, cover + 0.05, pn) * pw;
	}
	puddle *= 1.0 - side;
	gutter *= 1.0 - side;
	base *= mix(1.0, 0.62, damp);
	float standing = max(puddle, gutter);
	base *= 1.0 - 0.35 * standing;

	ALBEDO = base;
	// 0.07, not 0.18: at 0.18 the screen-space reflections blur into a warm smear, and a soaked
	// street at night is nearly a mirror - the lit windows and tail lights standing in it are
	// the whole look.
	ROUGHNESS = clamp(mix(mix(rough, 0.07, film), 0.02, standing), 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.85, max(film, gutter));
	// The gutter keeps a ripple of its own: running water is never mirror-flat, and its streaky
	// glints are what tell it from a puddle while the whole street is still glossy. The slopes
	// are mixed rather than the maps, so a dry street is exactly the texture at normal_depth.
	vec2 slope = (texture(normal_tex, uv).rg * 2.0 - 1.0) * (normal_depth * (1.0 - 0.6 * film) * (1.0 - puddle));
	slope = mix(slope, (flow_normal.rg * 2.0 - 1.0) * gutter_ripple, gutter);
	// Rain ringing the standing water. Faded out once a ring is under a few pixels (metres per
	// pixel from the derivatives, taken here in uniform control flow), where it would shimmer.
	float rain_now = clamp(rain_intensity, 0.0, 1.0);
	float near_px = 1.0 - smoothstep(0.012, 0.04, length(fwidth(w)));
	if (rain_now > 0.01 && ground_detail > 0.5) {
		if (standing > 0.01 && near_px > 0.0) {
			slope += rain_ripples(w, TIME) * ripple_strength * standing * near_px * sqrt(rain_now);
		}
	}
	// Godot rebuilds z from xy, so keep the slope inside the unit circle.
	slope *= min(1.0, 0.95 / max(length(slope), 1.0e-4));
	NORMAL_MAP = vec3(slope * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	vec3 glow = vec3(0.0);
	if (lamp_axis > 0 && lamp_factor > 0.001 && side < 0.5) {
		float far = smoothstep(street_glow_near, street_glow_far, length(VERTEX));
		if (far > 0.0) {
			glow = street_glow(plan_pos, slab_uv, lamp_axis) * lamp_ratio(plan_pos) * street_glow_level() * far;
		}
	}
	// The lit city standing in the water at night. Screen-space reflections only mirror what is
	// on screen, and a puddle at your feet mirrors the facades ABOVE the frame, so without this it
	// fell back to the night sky and read as a black hole; the web and the low levels have no SSR
	// at all. So the standing water mirrors a street canyon built from the reflected ray (lit shop
	// fronts along the bottom, office windows above, the roofline), sharp in puddles and the
	// gutter, and the wet film carries the same lights smeared into streaks toward the viewer.
	if (wet > 0.01 && lamp_factor > 0.05 && ground_detail > 0.5 && side < 0.5) {
		vec3 to_frag = normalize(world_pos - CAMERA_POSITION_WORLD);
		vec3 n = normalize(vec3(-slope.x * 0.6, 1.0, -slope.y * 0.6));
		vec3 r = reflect(to_frag, n);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(-to_frag.y, 0.0, 1.0), 5.0);
		vec3 city = mirrored_city(r, max(standing, 0.0));
		// The film is broken up where the tarmac is rough, so a streak runs in lengths.
		float film_break = smoothstep(0.35, 0.75, value_noise(w * 0.7 + seed));
		float gain = mirror_night * lamp_factor * fres * max(standing, film * mirror_film * film_break);
		glow += city * gain * near_mirror(length(VERTEX));
	}
	EMISSION = glow;
}
