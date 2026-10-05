shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ballpark's playing field (BallparkBuild), drawn analytically in the park's own frame: UV is
// local (u, v) metres - v from home plate toward centre field, u toward right field (Ballpark).
// The dimensions are Ballpark's: 90 ft bases, the rubber 60 ft 6 in out, the mound 18 ft across,
// the infield arc 95 ft from the rubber, the outfield fence (fence_r(), copied below), the warning
// track along the fence and the stands, the foul lines, batter's boxes, on-deck circles and a
// checked mow in the grass. Every line is box-filtered by its own screen width. Floodlit after
// dark (ballpark_common).

#include "res://shaders/ballpark_common.gdshaderinc"

uniform float flood_energy = 3.0;
uniform float base = 27.432;
uniform float rubber = 18.44;
uniform float mound_r = 2.74;
uniform float arc_r = 28.96;
uniform float fence_line = 100.6;
uniform float fence_alley = 114.3;
uniform float fence_center = 120.4;
uniform float track = 4.6;
uniform float front = 16.8;
uniform float mow = 4.6;

// Ballpark.fence_r(), the same function.
float fence_r(float deg) {
	float a = clamp(abs(deg), 0.0, 45.0);
	if (a <= 22.5) {
		float t = a / 22.5;
		return mix(fence_center, fence_alley, t * t);
	}
	float t2 = (a - 22.5) / 22.5;
	return mix(fence_alley, fence_line, t2 * (0.6 + 0.4 * t2));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 1 inside a band of width `w` around distance 0 (`d` signed or not), box-filtered.
float line(float d, float w) {
	float fw = max(fwidth(d), 1e-4);
	return clamp((w * 0.5 - abs(d)) / fw + 0.5, 0.0, 1.0);
}

// 1 inside (d < 0), filtered.
float inside(float d) {
	float fw = max(fwidth(d), 1e-4);
	return clamp(0.5 - d / fw, 0.0, 1.0);
}

void fragment() {
	vec2 q = UV;
	float pr = length(q);
	float deg = degrees(atan(q.x, q.y));
	// Along the first- and third-base lines.
	float a = (q.y + q.x) * 0.70710678;
	float b = (q.y - q.x) * 0.70710678;
	float fence = fence_r(deg);
	bool fair = abs(deg) <= 45.0 && q.y > 0.0;
	// Distance out from the foul lines (the V), behind and beside home.
	float da = (a > 0.0) ? abs(b) : length(q);
	float db = (b > 0.0) ? abs(a) : length(q);
	float out_v = min(da, db);
	vec3 grass = vec3(0.055, 0.17, 0.035);
	vec3 dirt = vec3(0.30, 0.135, 0.065);
	// The mow: a check of light and dark squares on the base lines' axes.
	float check = mod(floor(a / mow) + floor(b / mow), 2.0);
	float px = max(fwidth(a), fwidth(b)) / mow;
	check = mix(check, 0.5, smoothstep(0.2, 0.6, px));
	vec3 g = grass * (0.92 + 0.13 * check) * (0.92 + 0.16 * vnoise(q * 0.7));
	g *= 0.95 + 0.1 * vnoise(q * 9.0);
	vec3 col = g;
	float rough = 0.92;
	// Infield dirt: the arc round the rubber inside the lines (and a little past them), the
	// circle round home, the mound, cut-outs round the bases.
	vec2 mound_c = vec2(0.0, rubber - 0.15);
	float arc = length(q - vec2(0.0, rubber)) - arc_r;
	float dirt_d = max(arc, max(-(a + 1.5), -(b + 1.5)));
	dirt_d = min(dirt_d, length(q) - 3.96);
	dirt_d = min(dirt_d, length(q - mound_c) - mound_r);
	dirt_d = min(dirt_d, length(q - vec2(base * 0.70710678, base * 0.70710678)) - 2.9);
	dirt_d = min(dirt_d, length(q - vec2(-base * 0.70710678, base * 0.70710678)) - 2.9);
	// The infield grass square inside the base paths, less the circles above.
	float sq = max(max(1.0 - a, a - (base - 1.0)), max(1.0 - b, b - (base - 1.0)));
	sq = max(sq, -(length(q) - 3.96));
	sq = max(sq, -(length(q - mound_c) - mound_r));
	sq = max(sq, -(length(q - vec2(0.0, base * 1.41421356)) - 2.9));
	float is_dirt = inside(dirt_d) * (1.0 - inside(sq));
	// The warning track: inside the fence, and along the stands' wall in foul ground.
	float trk = fair ? inside(-(pr - (fence - track))) : inside(-(out_v - (front - track)));
	if (!fair && out_v < front - track) {
		trk = 0.0;
	}
	is_dirt = max(is_dirt, trk);
	vec3 d = dirt * (0.85 + 0.25 * vnoise(q * 1.3)) * (0.94 + 0.1 * vnoise(q * 11.0));
	// The mound is a shade lighter where it is raked.
	d *= 1.0 + 0.08 * inside(length(q - mound_c) - mound_r);
	col = mix(col, d, is_dirt);
	rough = mix(rough, 0.97, is_dirt);
	// Chalk: the foul lines out to the fence, the batter's boxes, the rubber, the on-deck circles.
	vec3 chalk = vec3(0.85, 0.86, 0.84);
	float lines_m = 0.0;
	if (a > 0.0 && a < 130.0) {
		lines_m = max(lines_m, line(b, 0.076));
	}
	if (b > 0.0 && b < 130.0) {
		lines_m = max(lines_m, line(a, 0.076));
	}
	for (int s = -1; s <= 1; s += 2) {
		vec2 bc = vec2(float(s) * 0.97, 0.0);
		vec2 h = vec2(0.61, 0.915);
		vec2 e = abs(q - bc) - h;
		float box = max(e.x, e.y);
		lines_m = max(lines_m, line(box, 0.076));
		float deck = length(q - vec2(float(s) * 11.5, -4.0)) - 0.76;
		col = mix(col, d * 0.9, inside(deck));
		lines_m = max(lines_m, line(deck, 0.07));
	}
	vec2 rub = abs(q - vec2(0.0, rubber)) - vec2(0.305, 0.076);
	lines_m = max(lines_m, inside(max(rub.x, rub.y)));
	col = mix(col, chalk, lines_m);
	// Beyond the fence (the gap to the pavilions): dark gravel.
	if (fair && pr > fence + 0.3) {
		col = vec3(0.08, 0.075, 0.07);
	}
	NORMAL_MAP = vec3(0.5 + 0.08 * (vnoise(q * 6.0) - 0.5), 0.5 + 0.08 * (vnoise(q * 6.0 + 3.7) - 0.5), 1.0);
	ALBEDO = cs_out(col);
	ROUGHNESS = rough;
	EMISSION = cs_out(col * bp_flood() * flood_energy * vec3(0.95, 0.98, 1.04));
}
