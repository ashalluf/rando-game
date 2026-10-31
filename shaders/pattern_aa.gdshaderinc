// Box-filtered repeating patterns for ground shaders (paving-aliasing, 2026-10-31).
//
// A pattern drawn with step() / smoothstep() on fract() is sampled once per pixel: past the
// distance where a period spans a couple of pixels it aliases into moire, and the old trick of
// widening the edge by fwidth() GROWS the line (a 6 mm deck gap 10 m off covered half the
// board). These functions integrate the pattern over the pixel's footprint instead (the exact
// box filter of a periodic pulse train, from its antiderivative), so a line is crisp up close,
// thins to grey lines, and at a distance is exactly its share of the surface: width / period.
//
// `fw` is the footprint in the pattern's units: fwidth() of the coordinate, taken by the
// caller in uniform control flow (never inside a branch: llvmpipe returns 0 there).
//
// PAVING_AA (a global, PavingAA.apply(); PAVING_AA=0 in the environment is the A/B) switches every
// user back to its old line: paa_on() is false and the caller keeps its own code.

global uniform float paving_aa;

bool paa_on() {
	return paving_aa > 0.5;
}

// The antiderivative of lines of width w (centred on every multiple of p), at s.
float paa_prim(float x, float p, float w) {
	float s = x / p + 0.5 * w / p;
	return floor(s) * w + min(fract(s) * p, w);
}

// Coverage (0..1) of lines w wide every p along x, averaged over a footprint fw wide.
float paa_lines(float x, float p, float w, float fw) {
	float f = max(fw, p * 1.0e-4);
	// Wider than a few periods: the integral is the average (and float precision runs out).
	if (f > p * 8.0) {
		return w / p;
	}
	return clamp((paa_prim(x + 0.5 * f, p, w) - paa_prim(x - 0.5 * f, p, w)) / f, 0.0, 1.0);
}

// A grid of joints: lines w wide every p along both axes (the union, filtered per axis).
float paa_grid(vec2 x, float p, float w, vec2 fw) {
	float a = paa_lines(x.x, p, w, fw.x);
	float b = paa_lines(x.y, p, w, fw.y);
	return a + b - a * b;
}

// A square wave (stripes / dashes): 1 for the first `duty` of every period p.
float paa_stripes(float x, float p, float duty, float fw) {
	// The lines of width duty * p centred at duty * p / 2.
	return paa_lines(x - 0.5 * duty * p, p, duty * p, fw);
}

// How much of a detail of `size` (pattern units) still resolves at footprint fw: 1 at two
// pixels across or more, 0 at one pixel or less. For details that cannot be integrated
// (cells, speckle): mix them toward their average with this.
float paa_keep(float size, float fw) {
	return 1.0 - smoothstep(0.5, 1.0, fw / max(size, 1.0e-6) * 2.0);
}

// A paving TEXTURE's pattern (setts, bricks, pavers) faded to the texture's own average once its
// module (one stone / course, in the caller's units) is under a couple of pixels. The mips do most
// of this, but they are picked by the minor axis under anisotropic filtering, and a grazing row
// of courses (the depth axis, where moire lives) can still beat against the pixel grid; this takes
// the MAJOR axis (`fw` = max of fwidth() over the coordinate), like the lettering and the joints.
// The mean is the texture's last mip, so no table to keep in step with the art.
vec3 paa_tex_mean(sampler2D tex) {
	return textureLod(tex, vec2(0.5), 14.0).rgb;
}

vec3 paa_tex_fade(vec3 sampled, vec3 mean, float module, float fw) {
	return mix(mean, sampled, paa_keep(module, fw));
}
