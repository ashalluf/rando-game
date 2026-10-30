// The night air round a light: what NightAtmos (scripts/world/night_atmos.gd) draws as a
// camera-facing halo quad round street lamp heads and lit shop fronts (night_halo.gdshader) and
// car_lights.gdshader round head and tail lamps. Shared so the three agree on how big and how
// bright a halo is in a given air.
//
// night_atmos (a shader global NightAtmos pushes four times a second):
//   x  haze, 0..1: how wet the air is (a Santa Ana night ~0.06, clear ~0.3, rain ~0.8, the marine
//      layer and a storm ~0.95). Halos grow and brighten with it; shafts need it.
//   y  shaft gain: 0 where Forward+'s volumetric fog already draws the lamps' light in the air.
//   z  halo gain: 0 turns every halo off (NIGHT_ATMOS=0 builds none; Quality's LOWEST dims them).
//   w  the viewport's height in pixels, to keep a far core a pixel or two across (VIEWPORT_SIZE
//      reads 1 in some vertex stages, CLAUDE.md's ridges trap).
// Shader includes use // comments.

global uniform vec4 night_atmos;

// Metres one pixel spans at view distance `dist` (abs(): the Compatibility projection's [1][1]
// is negative, CLAUDE.md's utility poles trap).
float nh_metre_px(float dist, mat4 proj) {
	return 2.0 * dist / (max(abs(proj[1][1]), 1e-3) * clamp(night_atmos.w, 64.0, 8192.0));
}

// A halo's world radius for a light whose base radius is `r0`: tight in dry air, swollen in mist.
float nh_radius(float r0) {
	return r0 * mix(0.55, 1.7, clamp(night_atmos.x, 0.0, 1.0));
}

// How much of the halo's wide glow the air carries (a dry night keeps only the lens's glint).
float nh_halo_amount() {
	float h = clamp(night_atmos.x, 0.0, 1.0);
	return 0.18 + 0.82 * h * h;
}

// The light lost to the air between the light and the eye: a wet night swallows the far lamps.
float nh_far(float dist) {
	return exp(-dist / mix(2400.0, 320.0, clamp(night_atmos.x, 0.0, 1.0)));
}

// A lens streak only on a light the camera looks nearly straight at and is close to: `c` is the
// light's view-space centre. 0..1.
float nh_streak(vec3 c, float dist) {
	if (c.z > -0.1) {
		return 0.0;
	}
	float off = length(c.xy) / -c.z;
	return (1.0 - smoothstep(0.05, 0.28, off)) * (1.0 - smoothstep(18.0, 75.0, dist));
}

// The halo's shape at `q` (the quad in halo radii: x spans +-ex): a hot core of radius `core_r`,
// the soft glow out to 1, and a thin horizontal streak out to ex.
float nh_shape(vec2 q, float ex, float core_r, float core_amp, float halo_amp, float streak_amp) {
	float r = length(q);
	float core = exp(-2.2 * (r * r) / max(core_r * core_r, 1e-6)) * core_amp;
	float glow = pow(max(1.0 - r, 0.0), 2.4) * halo_amp;
	float streak = 0.0;
	if (streak_amp > 0.0) {
		float along = max(1.0 - abs(q.x) / max(ex, 1.0), 0.0);
		streak = exp(-abs(q.y) * 26.0) * along * along * streak_amp;
	}
	return core + glow + streak;
}
