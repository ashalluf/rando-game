// Trees under light (tree-light-2, 2026-10-31; TreeLight, scripts/world/tree_light.gd). Shared by
// shaders/foliage_tex.gdshader (the scanned trees), shaders/foliage.gdshader (the palms) and
// shaders/la_tree.gdshader (the code-built LA trees). Include AFTER tree_wind.gdshaderinc.
//
// Two things a tree shader cannot get from the renderer:
//  * WEIGHT in the sway. A tree is a heavy spring: a tall one swings slower than a small one (its
//    natural rate falls about as 1 / sqrt(height)), it answers a gust late, leans into it, and
//    when the gust lets go it swings back past upright before it settles. One rate and a gust
//    applied at once read as every tree on the street wobbling like a toy on a spring.
//    tl_rate() is the rate, tl_load() the gust as the crown feels it (TreeLight.load_of() is the
//    GDScript copy: tests/tree_light_checks.gd holds them together).
//  * The light INSIDE a crown. Real leaves pass 10-20 % of the light that falls on them, layer
//    after layer, so a crown seen from below or with the sun behind it glows green-gold all
//    through, brightest where the path to the sky or the sun is shortest. Godot's BACKLIGHT is
//    only one layer deep and is multiplied by the shadow map, so on Forward+ the crown's own
//    shadow twin put every inner and lower leaf out: crowns were black-teal from the pavement.
//    tl_path() is the length of the path through the crown's ellipsoid toward a direction (the
//    sun's, the sky's) in crown radii; the shaders turn it into transmitted sky light and a
//    forward-scattered share of the sun (`tree_sun`, published by TreeLight: the sun's colour
//    times its energy, linear, 0 at night).

global uniform vec3 tree_sun;

/// The sway rate of a tree `height_m` tall against a 10 m one (a cantilever's rate falls about as
/// 1 / sqrt(height) for the same proportions), clamped to a sane band.
float tl_rate(float height_m) {
	return clamp(sqrt(10.0 / max(height_m, 1.0)), 0.6, 1.5);
}

/// How long a tree `height_m` tall takes to answer a gust, seconds.
float tl_lag(float height_m) {
	return clamp(0.35 + height_m * 0.05, 0.4, 1.6);
}

/// The gust as the crown feels it: the front late by the tree's lag, and an overshoot back past
/// upright while the gust is dropping (the swing-back), -0.35..1.3. `g` uses tw_gust().
float tl_load(vec2 world_xz, float t, vec2 lean, float height_m) {
	float lag = tl_lag(height_m);
	float g0 = tw_gust(world_xz, t - lag, lean);
	float g1 = tw_gust(world_xz, t - lag * 2.2, lean);
	// The swing-back: the drop over the last lag, applied the other way.
	return clamp(g0 + 0.9 * (g0 - g1), -0.35, 1.3);
}

/// Length of the path from `q` (a point in crown space: the crown's ellipsoid is the unit sphere)
/// out of the crown along unit direction `d` (also crown space, normalised), 0..2 crown radii.
float tl_path(vec3 q, vec3 d) {
	float b = dot(q, d);
	float c = dot(q, q) - 1.0;
	float disc = b * b - c;
	if (disc <= 0.0 || c > 0.0) {
		return 0.0;
	}
	return max(-b + sqrt(disc), 0.0);
}

/// Light that gets through `path` crown radii of leaves (a crown passes a little light right
/// through its middle, through the gaps, never none).
float tl_through(float path, float density) {
	return exp(-path * density) * 0.88 + 0.12 * exp(-path * density * 0.25);
}
