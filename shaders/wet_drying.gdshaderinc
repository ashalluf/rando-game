// How a street dries after the rain. Shared by road.gdshader, road_patch.gdshader and
// road_paint.gdshader, so a patch or a painted line dries in step with the tarmac under it.
//
// While it rains the street is evenly wet: `road_wetness` is the whole story. Once the rain stops
// Weather ramps `road_drying` to 1 and the same amount of water left (`road_wetness` still falls
// from 1 to 0) is spread unevenly: every spot has a `hold` (0 dries first, 1 last) and a spot is
// wet while the water left is above its threshold. Wheel tracks and pavements hold little, the
// gutters and the ground round the puddles a lot, and the rest is slow blotchy noise - so the
// dry front creeps across the street in ragged patches instead of the whole road fading evenly.
// All of it is in world space and unseeded, so the patches run on across junctions and roads.

global uniform float road_drying;
// How much of the drying time lies between the first spot to dry and the last (0..1), and how
// wide in wetness the edge of a drying patch is. A smaller edge gives crisper dry fronts.
uniform float dry_spread = 0.8;
uniform float dry_edge = 0.2;


float wet_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float wet_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = wet_hash(i);
	float b = wet_hash(i + vec2(1.0, 0.0));
	float c = wet_hash(i + vec2(0.0, 1.0));
	float d = wet_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


// The uneven part of a spot's hold: blotches about ten metres across with a ragged finer edge.
float wet_hold_noise(vec2 w) {
	float n = 0.65 * wet_noise(w * 0.11 + vec2(23.0, 7.0)) + 0.35 * wet_noise(w * 0.47 + vec2(3.0, 41.0));
	return 0.15 + 0.6 * smoothstep(0.22, 0.78, n);
}


// (film, damp) for a spot that holds `hold`, with `wet` of the water still about. `film` is
// standing water (gloss), `damp` the soaked-in darkening, which outlasts the film by a little -
// a drying street is dark and matte before it is dry. Both are `wet` while it rains.
vec2 wet_film_damp(float wet, float hold) {
	float t = (1.0 - clamp(hold, 0.0, 1.0)) * dry_spread;
	float fade = smoothstep(0.01, 0.1, wet);
	float film = smoothstep(t, t + dry_edge, wet) * fade;
	float damp = smoothstep(t - 0.2, t + dry_edge * 0.4, wet) * fade;
	return mix(vec2(wet), vec2(film, damp), clamp(road_drying, 0.0, 1.0));
}
