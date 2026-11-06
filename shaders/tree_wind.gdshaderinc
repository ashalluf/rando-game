// The street trees' wind (trees-closeup, 2026-10-30): ONE gust field every tree shader reads -
// shaders/foliage_tex.gdshader (the scanned trees, bushes and flowers), shaders/foliage.gdshader
// (the palms) and shaders/la_tree.gdshader (the code-built LA trees) - so a gust is something
// that crosses the street: the trees at one end bow, then the next ones, then the ones across the
// road, at TW_SPEED m/s downwind. The old envelope was one sine of (x + z) per tree, which had
// every tree on a street breathing in turn like a stadium wave and no front at all.
//
// The field is laid on the TRUE world (`origin_shift`, WorldState.world_offset), so an origin
// re-centre does not jump every crown. It runs downwind along the steady wind (`wind_lean`, the
// Santa Ana) when there is one, else along the prevailing onshore breeze (TW_DIR, the way the
// sea air comes off the Pacific: west to east, a little north). TreesCloseup.gust() is the same
// function in GDScript (tests/trees_closeup_checks.gd holds the two together: change one,
// change both).

global uniform vec3 origin_shift;

const vec2 TW_DIR = vec2(0.949, 0.316);
/// How fast a gust front runs downwind, metres a second.
const float TW_SPEED = 8.5;
/// Metres between gust crests along the wind, and the shorter wave riding on it.
const float TW_LEN = 74.0;
const float TW_LEN2 = 31.0;
/// How far a front is bent across the wind (metres of lag per metre across, as a wave).
const float TW_RAGGED = 9.0;

vec2 tw_dir(vec2 lean) {
	return dot(lean, lean) > 1e-6 ? normalize(lean) : TW_DIR;
}

// Gust strength 0..1 at a true-world point. Peaky on purpose: short strong fronts and long lulls,
// which is what a breeze on a street looks like (a sine spends as long at the top as the bottom).
float tw_gust(vec2 world_xz, float t, vec2 lean) {
	vec2 d = tw_dir(lean);
	float along = dot(world_xz, d) - t * TW_SPEED;
	float across = dot(world_xz, vec2(-d.y, d.x));
	along += sin(across * 0.031 + t * 0.07) * TW_RAGGED;
	float a = 0.5 + 0.5 * sin(along * (6.28318 / TW_LEN));
	float b = 0.5 + 0.5 * sin(along * (6.28318 / TW_LEN2) + 1.7 + across * 0.011);
	return a * a * (0.6 + 0.4 * b);
}

// The wind's direction in a model's own space (the instance may be turned and scaled), xz.
vec2 tw_dir_model(mat4 model, vec2 lean) {
	vec2 d = tw_dir(lean);
	vec3 m = transpose(mat3(model)) * vec3(d.x, 0.0, d.y);
	return normalize(m.xz + vec2(1e-6));
}
