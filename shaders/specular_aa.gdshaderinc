// Specular and edge anti-aliasing helpers (specular-aliasing pass, 2026-11-01; docs/HANDOFF.md
// "Shimmer and crawl in motion"). A glossy lobe narrower than a pixel's spread of normals and a
// cut-out or feature thinner than a pixel both sample ONE value per pixel per frame: in motion
// that value jumps, and the frame sparkles or crawls. These widen the lobe and fade the detail by
// the pixel's footprint instead, so motion moves a smooth image.
//
// SPECULAR_AA (a global, SpecularAA.install(); SPECULAR_AA=0 in the environment is the A/B): every
// caller keeps its old line while saa_on() is false.
//
// Derivatives: every function here takes them from its caller, who must take dFdx / dFdy / fwidth
// in uniform control flow (never inside a branch: llvmpipe returns 0 there).

global uniform float specular_aa;

bool saa_on() {
	return specular_aa > 0.5;
}

// Geometric specular AA (Kaplanyan 2016, Tokuyoshi 2019): roughness widened by the screen-space
// variance of the shading normal `n` (any space, unit length), `dn_dx` / `dn_dy` its derivatives.
// Forward+ already runs this on the final normal (the project's roughness limiter); the
// Compatibility renderer (the web, every opengl3 still) has nothing, so a caller that only wants
// what Godot leaves out wraps it in `#if CURRENT_RENDERER != RENDERER_FORWARD_PLUS`.
float saa_geometric(float rough, vec3 dn_dx, vec3 dn_dy, float amount, float limit) {
	float variance = amount * (dot(dn_dx, dn_dx) + dot(dn_dy, dn_dy));
	float k = min(2.0 * variance, limit);
	return sqrt(clamp(rough * rough + k, 0.0, 1.0));
}

// Normal-map minification (Toksvig, by footprint): a bump map's slopes average out in its mips,
// so a glossy surface far off draws the sharp lobe of the averaged (flat) normal and every texel
// that still bends it flashes. `slope_var` is the map's slope variance at full detail (times the
// normal depth squared); `texels` how many of its texels one pixel covers (the footprint in UV
// times the map's size). The variance the mips threw away goes into the roughness instead.
float saa_minified(float rough, float slope_var, float texels) {
	float lost = slope_var * clamp(1.0 - 1.0 / max(texels * texels, 1.0), 0.0, 1.0);
	return sqrt(clamp(rough * rough + lost, 0.0, 1.0));
}

// The pixel's footprint in metres at view-space depth `dist` (PROJECTION_MATRIX[1][1] is
// abs()'d: Compatibility hands it negative).
float saa_px_m(float dist, mat4 proj, vec2 viewport) {
	return dist * 2.0 / max(abs(proj[1][1]) * viewport.y, 1.0);
}

// A sharp highlight (pow(x, shine)) widened to what the pixel can hold: the exponent comes down as
// the normal varies across the pixel, and the energy is kept (a wider lobe is a dimmer one), so a
// glint fades into a soft sheen rather than flashing pixel to pixel. Returns the exponent to use;
// multiply the lobe by saa_shine_gain() of the same pair.
float saa_shine(float shine, vec3 dn_dx, vec3 dn_dy) {
	float var = dot(dn_dx, dn_dx) + dot(dn_dy, dn_dy);
	// A Phong lobe of exponent s is ~ a Gaussian of variance 1 / s in the half angle.
	return 1.0 / (1.0 / max(shine, 1.0) + 0.5 * var);
}

float saa_shine_gain(float shine, float widened) {
	return clamp((widened + 2.0) / (shine + 2.0), 0.0, 1.0);
}

// A per-pixel threshold for coverage-by-dither (alpha-to-coverage without MSAA): a feature too
// small to draw is kept at `cover` where saa_dither() < cover. On Forward+ the threshold changes
// every frame, so TAA resolves it to the exact share (foliage_tex's rule); on Compatibility (no
// temporal pass) it is a fixed 4 x 4 ordered pattern, so a region of steady cover is a steady
// screen of the right density rather than features flicking on and off as the camera moves.
float saa_dither(vec2 frag, float t) {
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	return fract(sin(dot(frag + vec2(fract(t * 7.13) * 61.0, fract(t * 3.71) * 37.0), vec2(12.9898, 78.233))) * 43758.5453);
#else
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
#endif
}

// Coverage of a centred box `2 h` wide every `1` (cell units) over a footprint `fw` (cell units)
// at `x` (cell units, continuous across cells): the exact box filter of a periodic pulse.
float saa_prim(float x, float w) {
	float s = x + 0.5 * w;
	return floor(s) * w + min(fract(s), w);
}

float saa_pulse(float x, float c, float h, float fw) {
	float f = max(fw, 1.0e-4);
	if (f > 8.0) {
		return 2.0 * h;
	}
	float xc = x - c;
	return clamp((saa_prim(xc + 0.5 * f, 2.0 * h) - saa_prim(xc - 0.5 * f, 2.0 * h)) / f, 0.0, 1.0);
}
