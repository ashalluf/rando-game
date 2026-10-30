// The lawn's field (2026-10-30, fleet wave 3 "lawns-closeup", docs/HANDOFF.md "Lawns close up"):
// everything about a lawn that is a pattern on the ground - watered against parched, clover
// patches, worn dirt, mower stripes, the morning sprinklers - as functions of TRUE world XZ and
// the lawn's own numbers (its seed uniform, its dryness, whether it is striped). Included by
// lawn.gdshader, which draws the ground, AND by grass.gdshader, whose blades take the field at
// their root: a blade over a dry patch is straw, over clover short and blue-green, over a worn
// patch flattened into the dirt, and every blade has the colour of the lawn under it - so when
// the blades shrink away with distance there is no band where the grass changes colour.
//
// The arithmetic is the renderer's own space, as lawn.gdshader always was (the tints are
// `source_color` uniforms there and arrive decoded on Forward+, raw on Compatibility; grass.gdshader
// hands its copies through cs_as_uniform() to match). lawn_field_on() is the A/B: LAWNS_CLOSEUP=0
// sets the `lawns_closeup` global to 0 and every caller takes its old path.
// LawnsCloseup (scripts/world/lawns_closeup.gd) mirrors lf_sprinkler_hours(); the checks hold them.
// Shader includes use // comments.

global uniform float lawns_closeup;

bool lawn_field_on() {
	return lawns_closeup > 0.5;
}


float lf_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float lf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = lf_hash(i);
	float b = lf_hash(i + vec2(1.0, 0.0));
	float c = lf_hash(i + vec2(0.0, 1.0));
	float d = lf_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float lf_fbm(vec2 p) {
	return lf_noise(p) * 0.6 + lf_noise(p * 2.3 + 11.0) * 0.28 + lf_noise(p * 5.1 + 31.0) * 0.12;
}


// Watered against parched, 0..1. The first line is lawn.gdshader's old patch field exactly; on
// top of it the close-up adds the small brown spots a real lawn has (a sprinkler's dry crescent,
// a dog's spot, a hot corner) and the drying a lawn does along hot concrete (`edge_m`, metres to
// the lawn's edge; large when unknown).
float lf_dry(vec2 wp, float lseed_, float dry_amt, float edge_m) {
	float dry = clamp(lf_fbm(wp * 0.055 + lseed_ * 1.7) * 0.9 + (dry_amt - 0.5) * 0.8, 0.0, 1.0);
	float spots = smoothstep(0.68, 0.86, lf_noise(wp * 0.42 + lseed_ * 2.9 + 17.0)) * (0.35 + 0.65 * dry_amt);
	float edge = (1.0 - smoothstep(0.15, 1.1, edge_m)) * 0.35;
	return clamp(dry + spots * 0.55 + edge, 0.0, 1.0);
}


// Clover and broadleaf weeds through a watered lawn, in patches a metre or three across: none in
// the parched ground (clover is the first thing a dry summer kills).
float lf_clover(vec2 wp, float lseed_, float dry) {
	float c = smoothstep(0.64, 0.80, lf_noise(wp * 0.31 + lseed_ * 3.1 + 71.0) * 0.75 + lf_noise(wp * 1.3 + 5.0) * 0.25);
	return c * (1.0 - smoothstep(0.35, 0.75, dry));
}


// Worn dirt where feet go (lawn.gdshader's own field).
float lf_wear(vec2 wp, float lseed_, float w_amt) {
	return smoothstep(0.62, 0.86, lf_fbm(wp * 0.09 + 57.0 + lseed_)) * w_amt;
}


// The mower stripe's sheen, -1..1 (0 with no stripes).
float lf_stripe(vec2 wp, float lseed_, float s_width) {
	if (s_width <= 0.01) {
		return 0.0;
	}
	float a = lseed_ * 0.9;
	vec2 dir = vec2(cos(a), sin(a));
	return sin(dot(wp, dir) * 3.14159 / s_width);
}


// How much of the morning's watering is still on the grass at city_hour `h`: the sprinklers run
// before dawn into the early morning and the water is gone by mid-morning (LawnsCloseup's mirror).
float lf_sprinkler_hours(float h) {
	return smoothstep(4.6, 5.4, h) * (1.0 - smoothstep(8.2, 10.4, h));
}


// Where the sprinklers wet this lawn, 0..1: pop-up heads on a jittered 7 m grid, each throwing a
// circle about 4.5 m round with the throw thinning at its edge; only most lawns are watered on a
// given morning (a hash of the lawn), and none once the hour is past.
float lf_sprinkler(vec2 wp, float lseed_, float hour) {
	float t = lf_sprinkler_hours(hour);
	if (t <= 0.0 || lf_hash(vec2(lseed_ * 7.13, 3.7)) > 0.72) {
		return 0.0;
	}
	vec2 g = wp / 7.0;
	vec2 i = floor(g);
	float w = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 c = i + vec2(float(dx), float(dy));
			vec2 head = (c + 0.5 + (vec2(lf_hash(c + lseed_), lf_hash(c + lseed_ + 9.1)) - 0.5) * 0.7) * 7.0;
			float d = length(wp - head);
			w = max(w, 1.0 - smoothstep(3.0, 4.8, d + lf_noise(wp * 1.7 + c) * 0.9));
		}
	}
	return w * t;
}


// The lawn's colour multiplier (renderer space) at `wp` from its tints and the fields, and how much
// is worn bare: what lawn.gdshader multiplies its texture by, and what a blade wears at its root.
vec3 lf_tone(vec2 wp, float lseed_, vec3 t_wet, vec3 t_dry, vec3 t_dirt, float dry, float clover, float stripe, float s_amt, float wear) {
	vec3 col = mix(t_wet, t_dry, dry);
	// Clover reads a cooler, bluer green than the grass round it, and a touch darker.
	col = mix(col, t_wet * vec3(0.80, 0.98, 1.10), clover * 0.75);
	col *= 1.0 + stripe * s_amt;
	return mix(col, t_dirt, wear);
}
