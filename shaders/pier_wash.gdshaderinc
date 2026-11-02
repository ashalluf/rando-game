// The piers' lamps lighting what is round them at night (RcPierNight, refcam pier_night): the sand
// beside and beyond a pier (beach_sand.gdshader) and the sea round its piles (ocean.gdshader).
// Every pier's lamp rows are LINE sources: Weather's pier_light_lines() (the same rows the ocean
// mirrors), lamps `pw_info.y` apart at height `pw_info.x`. A continuous row of isotropic lamps of
// intensity I lights a horizontal surface H under it, r = sqrt(d^2 + H^2) from its line, with
//   E = (I / spacing) * H / r^2 * [u / sqrt(u^2 + r^2)] over the row's two ends u,
// which is what pw_row() returns (per unit I / spacing). The deck the lamps stand on shades the
// ground on its own side of the row (`pw_side`: which side of a->b the deck is, +1 left of the
// row, -1 right, 0 none), softened over a couple of metres. Plus up to PW_PTS point glows (the
// midway's carousel, wheel, arcade: xyz true world, w intensity; colour in pw_pt_col).
// Host shader: declares `global uniform float lamp_factor;`; pw_gain 0 (the default) is no light.

#define PW_LINES 10
#define PW_PTS 8

uniform vec4 pw_lines[10];
uniform vec4 pw_info[10];
uniform float pw_side[10];
uniform int pw_count = 0;
uniform vec4 pw_pts[8];
uniform vec3 pw_pt_col[8];
uniform int pw_pt_count = 0;
// Lamp intensity per metre of row (I / spacing), and the points' scale.
uniform float pw_gain = 0.0;
uniform float pw_pt_gain = 1.0;

float pw_row(vec2 p, float y, vec4 pl, vec4 info, float side) {
	vec2 a = pl.xy;
	vec2 ab = pl.zw - pl.xy;
	float len = max(length(ab), 0.01);
	vec2 dir = ab / len;
	vec2 m = vec2(-dir.y, dir.x);
	float u = dot(p - a, dir);
	float d = dot(p - a, m);
	float h = max(info.x - y, 0.5);
	float r2 = d * d + h * h;
	float r = sqrt(r2);
	float u0 = -u - info.y * 0.5;
	float u1 = len - u + info.y * 0.5;
	float e = h / r2 * (u1 / sqrt(u1 * u1 + r2) - u0 / sqrt(u0 * u0 + r2));
	// The deck's own side, under it: shaded (the lamps stand on it).
	float inward = d * side;
	e *= 1.0 - smoothstep(0.5, 2.5, inward) * step(0.5, abs(side)) * step(y, info.z);
	return e;
}

// The light (linear, a white-ish warm) falling on a horizontal surface at true-world `tw`.
vec3 pier_wash(vec3 tw) {
	vec3 e = vec3(0.0);
	if (pw_gain <= 0.0) {
		return e;
	}
	for (int i = 0; i < PW_LINES; i++) {
		if (i >= pw_count) {
			break;
		}
		vec4 info = pw_info[i];
		vec3 lc = mix(vec3(1.0, 0.80, 0.55), vec3(1.0, 0.58, 0.28), info.w);
		e += lc * pw_row(tw.xz, tw.y, pw_lines[i], info, pw_side[i]);
	}
	e *= pw_gain;
	for (int k = 0; k < PW_PTS; k++) {
		if (k >= pw_pt_count) {
			break;
		}
		vec4 pt = pw_pts[k];
		vec3 dv = pt.xyz - tw;
		float h = max(dv.y, 0.5);
		float r2 = dot(dv, dv) + 1.0;
		e += pw_pt_col[k] * pt.w * pw_pt_gain * h / (r2 * sqrt(r2));
	}
	return e;
}
