shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ballpark's seating bowl and pavilion bleachers (BallparkBuild): the stepped rows are real
// geometry, the seats and the crowd in them are drawn here. UV.x is metres along the row, UV.y
// the row number plus where on it: 0 .. RISER the riser at the row's front (bottom to top),
// RISER .. 1 the tread (front to back). COLOR.rgb is the tier's seat colour (sRGB), COLOR.a how
// full the tier is.
//
// What the eye reads from the field is the risers and the front of each tread, which is where a
// SEATED person of the row below stands in front of them: so a riser shows the torso of whoever
// sits in the row below (or that seat's back, when it is empty), the front of the tread their
// head, and the back of the tread the seat itself (or a lap). Under a pixel a seat is its average:
// the tier's colour and its crowd mixed by how full it is.

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float flood_energy = 0.26;
uniform float seat_pitch = 0.5;
uniform float aisle_every = 14.0;
uniform float aisle_width = 1.3;
const float RISER = 0.3;
// StadiumNight (0 = the old look): sections fuller or emptier than their tier, and the rows
// under the deck above (or the top deck's roof) out of the light banks' reach after dark.
uniform float night2 = 0.0;
uniform float shade_floor = 0.2;

varying vec3 seat;
varying float fill;

void vertex() {
	seat = bp_vcol(COLOR.rgb);
	fill = COLOR.a;
}

vec3 shirt_raw(float h) {
	// Mostly a home crowd in blue and white, the rest anything.
	if (h < 0.30) return vec3(0.04, 0.12, 0.42);
	if (h < 0.48) return vec3(0.78, 0.8, 0.82);
	if (h < 0.58) return vec3(0.03, 0.03, 0.035);
	if (h < 0.66) return vec3(0.25, 0.26, 0.28);
	if (h < 0.72) return vec3(0.55, 0.06, 0.05);
	if (h < 0.77) return vec3(0.75, 0.6, 0.1);
	if (h < 0.83) return vec3(0.12, 0.3, 0.75);
	if (h < 0.88) return vec3(0.06, 0.25, 0.12);
	if (h < 0.93) return vec3(0.45, 0.32, 0.2);
	return vec3(0.6, 0.2, 0.4);
}

// Shirts, a little muted: a crowd seen across a ballpark is a mosaic, not confetti.
vec3 shirt(float h) {
	vec3 c = shirt_raw(h);
	return mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), 0.3);
}

vec3 skin(float h) {
	return mix(vec3(0.62, 0.42, 0.3), vec3(0.16, 0.09, 0.06), h);
}

void fragment() {
	float row = floor(UV.y);
	float f = UV.y - row;
	float sx = UV.x / seat_pitch;
	float sidx = floor(sx);
	float fx = sx - sidx;
	vec3 concrete = vec3(0.32, 0.31, 0.29);
	// Aisles: concrete steps, no seats.
	float ax = abs(fract(UV.x / aisle_every + 0.5) - 0.5) * aisle_every;
	float aisle = 1.0 - step(aisle_width * 0.5, ax);
	int ri = int(row);
	int si = int(sidx);
	// Which tier this is, from its fill (BallparkBuild's TIERS / the pavilions): the row from
	// which the deck above shades it (99 = open to the sky).
	float shade_row = 99.0;
	int tier = 4;
	if (fill > 0.83) { shade_row = 21.0; tier = 0; }
	else if (fill > 0.76) { shade_row = 15.0; tier = 1; }
	else if (fill > 0.67) { shade_row = 17.0; tier = 2; }
	else if (fill < 0.59) { shade_row = 10.0; tier = 3; }
	float fill0 = fill;
	float ff = fill;
	if (night2 > 0.0) {
		// A section between two aisles is fuller or emptier than its tier (behind the plate and
		// low down fuller, the corners of the upper decks thin), and a patch of a few rows
		// within it now and then a group's empty block.
		int sec = int(floor(UV.x / aisle_every));
		float sf = mix(0.5, 1.3, bp_hash01(sec * 13 + tier, 5101));
		float patch = bp_hash01(sec * 7 + tier * 3, int(floor(row / 5.0)) + 6200);
		sf *= patch < 0.18 ? 0.45 : 1.0;
		ff = clamp(mix(fill0, fill0 * sf, night2), 0.0, 0.97);
	}
	float occ_below = step(bp_hash01(si * 3 + 1, ri - 1), ff);
	float occ_here = step(bp_hash01(si * 3 + 1, ri), ff);
	float tone_below = bp_hash01(si * 5 + 2, ri - 1 + 4000);
	float tone_here = bp_hash01(si * 5 + 2, ri + 4000);
	vec3 col;
	// The seat's outline: a gap between seats.
	float gap = smoothstep(0.04, 0.0, min(fx, 1.0 - fx));
	if (f < RISER) {
		float h = f / RISER;
		// The row below: its seat back, or the torso of who sits in it.
		vec3 back = seat * (0.72 + 0.18 * h);
		vec3 torso = shirt(tone_below);
		float body = occ_below * smoothstep(0.08, 0.16, fx) * smoothstep(0.92, 0.84, fx);
		col = mix(back, torso, body);
		col = mix(col, concrete * 0.6, gap * (1.0 - body));
	} else {
		float t = (f - RISER) / (1.0 - RISER);
		if (t < 0.38) {
			// The front of the tread: the walkway, and the head and shoulders of the row below.
			vec2 hp = vec2(fx - 0.5, t / 0.38 - 0.35);
			float head = occ_below * (1.0 - smoothstep(0.17, 0.22, length(hp * vec2(1.0, 0.8))));
			float hair = step(0.5, bp_hash01(si * 7 + 3, ri - 1));
			vec3 skin_c = skin(bp_hash01(si * 11 + 5, ri - 1));
			vec3 head_c = mix(skin_c, mix(vec3(0.05, 0.04, 0.035), shirt(tone_below), step(0.8, tone_below)), hair * step(0.0, hp.y));
			col = mix(concrete, head_c, head);
		} else {
			// The seat itself, or someone's lap.
			float tt = (t - 0.38) / 0.62;
			vec3 pan = seat * (0.9 + 0.1 * tt);
			vec3 lap = mix(shirt(tone_here) * 0.85, vec3(0.08, 0.1, 0.16), smoothstep(0.3, 0.7, tt));
			float body = occ_here * smoothstep(0.1, 0.18, fx) * smoothstep(0.9, 0.82, fx);
			col = mix(pan, lap, body);
			col = mix(col, concrete * 0.7, gap * (1.0 - body));
		}
	}
	col = mix(col, concrete * (0.9 + 0.1 * f), aisle);
	// Under a pixel: the tier's colour and its crowd by how full it is.
	vec3 crowd_avg = vec3(0.13, 0.13, 0.16);
	vec3 avg = mix(mix(seat * 0.85, crowd_avg, ff * 0.7), concrete, aisle_width / aisle_every);
	if (night2 > 0.0) {
		// From the hills a crowd is a mosaic, not a tint: groups of a few seats over two rows each
		// their own mix of shirts, emptier groups showing the seats, the aisles' concrete between.
		int gx = int(floor(UV.x / (seat_pitch * 3.0)));
		int gy = int(floor(row / 2.0));
		float g_occ = clamp(ff + (bp_hash01(gx * 17 + tier, gy + 7100) - 0.5) * 0.7, 0.0, 1.0);
		vec3 g_shirt = mix(shirt(bp_hash01(gx * 3 + 1, gy + 7300)), shirt(bp_hash01(gx * 3 + 2, gy + 7400)), 0.5);
		vec3 g_crowd = mix(g_shirt, skin(bp_hash01(gx, gy + 7500)), 0.22);
		vec3 mosaic = mix(seat * 0.78, g_crowd, g_occ * 0.92);
		avg = mix(avg, mix(mosaic, concrete, aisle_width / aisle_every), night2);
	}
	float px = max(fwidth(UV.x) / seat_pitch, fwidth(UV.y) * 1.5);
	// The second pass hands over sooner: half-resolved rows beat into rings round the bowl.
	col = mix(col, avg, night2 > 0.0 ? smoothstep(0.15, 0.55, px) : smoothstep(0.35, 1.0, px));
	vec3 alb = col;
	float lit = 1.0;
	if (night2 > 0.0) {
		// Under the overhang: the banks on the roof cannot see these rows; the concourse's warm
		// lights and the bounce off the field are what reach them.
		float under = smoothstep(shade_row - 1.5, shade_row + 1.0, row);
		lit = mix(1.0, shade_floor, under * night2);
		alb *= mix(1.0, 0.9, under * night2);
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = 0.75;
	vec3 e = alb * bp_flood() * flood_energy * lit;
	if (night2 > 0.0 && lit < 0.999) {
		e += alb * vec3(1.0, 0.82, 0.6) * bp_flood() * flood_energy * 0.18 * (1.0 - lit);
	}
	EMISSION = cs_out(e);
}
