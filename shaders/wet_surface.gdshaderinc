// The world in the rain (wet-world): what every surface that is not a road does with the water
// Weather publishes - car paint and glass, building walls and roofs, awnings, the crowd's clothes and
// hair. Included by car_paint.gdshaderinc, car_glass(_damage).gdshader, car_wiper.gdshader,
// building.gdshader, building_lod.gdshader, facade_kit.gdshaderinc, rooftop.gdshader,
// character.gdshader and crowd_hair.gdshader. No textures (no sampler is spent anywhere).
//
// The road's numbers drive it: `road_wetness` (0..1, rising as the rain soaks the city, falling as
// it dries), `road_drying` (1 once the rain has stopped and the street is drying) and
// `rain_intensity` (how hard it rains now: drops land, runs flow, wipers sweep). A dry city costs
// every including shader one branch: everything here is called inside `if (ws_on())`.
//
// Never include this and wet_drying.gdshaderinc in one shader (both declare road_drying).

global uniform float road_wetness;
global uniform float road_drying;
global uniform float rain_intensity;
// 0 turns all of this off (WET_WORLD=0 in the environment, WetWorld.install()): the A/B.
global uniform float wet_world;

// Below this the world is dry and nothing here runs.
const float WS_DRY = 0.003;


// The one branch a dry city pays: is there water about at all?
bool ws_on() {
	return road_wetness > WS_DRY && wet_world > 0.5;
}


float ws_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 ws_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


float ws_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ws_hash(i), ws_hash(i + vec2(1.0, 0.0)), f.x),
		mix(ws_hash(i + vec2(0.0, 1.0)), ws_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


// The drying half of ws_wet(): how wet a spot holding `hold` still is once the rain has stopped.
float ws_dry(float hold) {
	float w = clamp(road_wetness, 0.0, 1.0);
	float t = (1.0 - clamp(hold, 0.0, 1.0)) * 0.85;
	return smoothstep(t, t + 0.18, w) * smoothstep(0.005, 0.06, w);
}


// How wet a surface is that holds `hold` of the water (0 dries first, 1 last). While it rains it is
// just `road_wetness`, like the street; drying, a spot is wet while the water left is over its
// threshold, so a wall dries from its sunny, open parts first and its streaks and ledges last - the
// same rule as the street's drying (wet_drying.gdshaderinc), in step with it.
float ws_wet(float hold) {
	return mix(clamp(road_wetness, 0.0, 1.0), ws_dry(hold), clamp(road_drying, 0.0, 1.0));
}


// A wall in the rain (building.gdshader, building_lod.gdshader: the near and the far city draw
// the same): `down` metres under the wall's top (< 0 unknown: a tower's curved faces), `up` metres
// over its foot, `streak` 0..1 how much water runs down this column (under a sill, off the coping).
// The rain wets a facade from the top down - the front reaches further the longer it rains
// (`road_wetness`) and runs ahead down the streaks, and a long hard rain wets the whole height a
// little - with the splash zone at the foot wet at once;
// drying, the open wall goes first and the streaks and the foot last.
float ws_wall(float down, float up, float streak) {
	float w = clamp(road_wetness, 0.0, 1.0);
	float reach = w * 60.0 + streak * w * 40.0 + 1.5;
	float front = down < 0.0 ? smoothstep(0.0, 0.25, w) : 1.0 - smoothstep(reach - 3.0, reach, down);
	float splash = (1.0 - smoothstep(0.35, 0.9, up)) * smoothstep(0.0, 0.15, w);
	// A long hard rain driven by the wind wets a tall wall all the way down, past the front.
	float driven = 0.6 * smoothstep(0.45, 1.0, w);
	float raining = max(max(front * mix(0.8, 1.0, streak), splash), driven);
	float drying = ws_dry(0.2 + 0.55 * streak + 0.5 * (1.0 - smoothstep(0.3, 1.2, up)));
	return mix(raining, drying, clamp(road_drying, 0.0, 1.0));
}


// How hard it is raining onto a surface right now (0 once the rain has stopped: no new drops land,
// nothing runs).
float ws_rain() {
	return clamp(rain_intensity, 0.0, 1.0) * (1.0 - clamp(road_drying, 0.0, 1.0));
}


// One layer of water beads on a surface: `p` metres in its plane, `cell` the spacing (m), `fill`
// the share of cells holding a bead, `px` metres a pixel covers. Returns (cover, slope across,
// slope up): each bead is a dome whose rim is antialiased by `px`; a bead under about a pixel
// gives no slope, only its share of cover (the water's average).
vec3 ws_bead_layer(vec2 p, float cell, float fill, float px, float salt) {
	vec2 g = p / cell + salt;
	vec2 i = floor(g);
	vec2 f = fract(g);
	float there = step(ws_hash(i + 1.7), fill);
	float r = mix(0.07, 0.3, pow(ws_hash(i + 9.3), 1.6));
	vec2 c = vec2(r) + (vec2(1.0) - 2.0 * r) * ws_hash2(i + 4.1);
	vec2 d = (f - c) / r;
	float q = length(d);
	float aa = px / max(r * cell, 1e-5);
	float resolved = smoothstep(0.35, 1.3, 1.0 / max(aa, 1e-5));
	float cover = there * (1.0 - smoothstep(1.0 - aa, 1.0 + aa, q));
	// Unresolved, a bead is its area: about PI r^2 of the cell.
	float mean = fill * 3.1416 * 0.035;
	vec2 slope = d * cover * 1.6 * resolved;
	return vec3(mix(mean, cover, resolved), slope);
}


// Beads at two sizes (a few fat drops among many small ones), `size` scales both (1 = cells 12.5
// and 5.2 mm apart). `amount` 0..1 fills them in.
vec3 ws_beads(vec2 p, float size, float amount, float px) {
	// Each layer on its own skewed lattice, or the beads line up in rows.
	vec2 pa = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * p;
	vec2 pb = mat2(vec2(0.62, -0.78), vec2(0.78, 0.62)) * p;
	vec3 a = ws_bead_layer(pa, 0.0125 * size, 0.6 * amount, px, 0.0);
	vec3 b = ws_bead_layer(pb, 0.0052 * size, 0.75 * amount, px, 37.0);
	vec2 sa = mat2(vec2(0.96, -0.28), vec2(0.28, 0.96)) * a.yz;
	vec2 sb = mat2(vec2(0.62, 0.78), vec2(-0.78, 0.62)) * b.yz;
	return vec3(max(a.x, b.x), sa + sb * (1.0 - a.x));
}


// Water running down a surface: `p.x` across, `p.y` DOWN it (metres), streams `spacing` apart,
// each wandering, a drop running down it at its own speed with a wet trail behind; `t` is time (s)
// and `flow` 0..1 how many streams run. Returns (wet, slope across).
vec2 ws_runs(vec2 p, float spacing, float t, float flow, float px) {
	float col = floor(p.x / spacing);
	float h0 = ws_hash(vec2(col, 7.1));
	float h1 = ws_hash(vec2(col, 13.7));
	float h2 = ws_hash(vec2(col, 29.3));
	if (h2 > flow) {
		return vec2(0.0);
	}
	float x0 = (col + 0.25 + 0.5 * h0) * spacing;
	float wob = (sin(p.y * (2.6 + 5.0 * h1) + h0 * 31.0) * 0.6 + sin(p.y * (9.0 + 7.0 * h0) + h1 * 17.0) * 0.4) * spacing * 0.12;
	float half_w = mix(0.0012, 0.0035, h1);
	float dx = p.x - x0 - wob;
	float aa = max(px, 1e-5);
	float line = 1.0 - smoothstep(half_w, half_w + aa, abs(dx));
	// The drop: it comes down at `speed`, once every `period` metres, and leaves a trail `len` long
	// that thins behind it.
	float speed = mix(0.06, 0.32, h0);
	float period = mix(0.8, 2.4, h2);
	float len = mix(0.25, 0.9, h1);
	float behind = fract((t * speed - p.y) / period + h1) * period;
	float trail = (1.0 - smoothstep(0.0, len, behind)) * smoothstep(0.0, 0.02, behind + 0.004);
	float head = 1.0 - smoothstep(0.0, 0.012, abs(behind - 0.006));
	float wet = line * max(trail * 0.85, head);
	// Under a pixel a run is a faint darker line, no slope.
	float resolved = smoothstep(0.5, 1.5, half_w / aa);
	float slope = line * clamp(dx / half_w, -1.0, 1.0) * resolved * (0.6 + head);
	return vec2(wet * mix(0.4, 1.0, resolved), slope);
}


// A tangent frame for a surface normal `n` (any space whose y is up): `t` across, `b` up the slope.
void ws_frame(vec3 n, out vec3 t, out vec3 b) {
	vec3 up = abs(n.y) > 0.92 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	t = normalize(cross(up, n));
	b = cross(n, t);
}
