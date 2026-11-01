shader_type canvas_item;

// The lens: a full-screen darkening toward the corners, a hair of colour fringing out at the
// edges, and a fine moving grain. Every camera lens does the first two and every film stock
// has the third, and a clean render with none of them is what reads as "a game" rather than as
// footage. Kept subtle on purpose - if you can see any one of them, it is too strong.
// It reads the 3D picture (this layer draws after it) and writes it back, so it is one cheap
// full-screen pass under the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.30;
// Where the falloff starts, as a fraction of half the screen diagonal, and how soft it is.
uniform float radius : hint_range(0.1, 1.2) = 0.46;
uniform float softness : hint_range(0.05, 2.0) = 0.85;
// Lateral colour at the frame edge, as a fraction of the screen width: red out, blue in.
uniform float fringe : hint_range(0.0, 0.01) = 0.0016;
// Film grain amplitude (0 off). Luminance only, strongest in the mid-tones, re-rolled every
// frame at a fixed rate so it does not crawl with the frame rate.
uniform float grain : hint_range(0.0, 0.2) = 0.028;
uniform float grain_fps = 24.0;

// CameraLens (scripts/player/camera_lens.gd) sets the rest; their defaults leave this pass exactly
// as it was (CAMERA_LENS=0, the test room without a lens, the web's flare).
// 0 the old grain, 1 film grain: triangular noise, strongest in the shadows, none in highlights.
uniform int lens_mode = 0;
// Grain multiplier from the exposure (the camera opened up in the dark shows more).
uniform float grain_gain = 1.0;
// The sun flare: its weight (0 = off, no taps), the sun's place in the frame (0..1, may be
// outside it), the frame's width over its height and the sun's colour (display numbers).
uniform float flare_amount = 0.0;
uniform vec2 sun_uv = vec2(0.5);
uniform float aspect = 1.7778;
uniform vec3 sun_tint = vec3(1.0, 0.95, 0.86);
// Strengths of the parts: the glow round the sun, the aperture spikes, the ghosts, and the veil
// over the whole frame shooting into the sun.
uniform float flare_glow = 0.30;
uniform float flare_spikes = 0.10;
uniform float flare_ghosts = 0.045;
uniform float flare_veil = 0.045;

// A regular hexagon's distance (the aperture's six blades), r its inner radius.
float hex_d(vec2 p, float r) {
	p = abs(p);
	return max(dot(p, vec2(0.8660254, 0.5)), p.y) - r;
}

// The flare in display numbers at `uv` (screen heights in `d` are aspect-corrected).
vec3 sun_flare(vec2 uv, float vis) {
	vec2 asp = vec2(aspect, 1.0);
	vec2 d = (uv - sun_uv) * asp;
	float r = length(d);
	// A tight glow and a long soft tail round the sun (the lens's own scatter).
	float glow = exp(-r * 18.0) * 0.6 + 0.4 / (1.0 + r * r * 90.0);
	// Six thin spikes from the blades, fading out over a third of the frame.
	float a = atan(d.y, d.x) + 0.21;
	float spikes = pow(abs(cos(a * 3.0)), 260.0) * exp(-r * 7.0)
			+ pow(abs(cos(a * 3.0 + 1.5708)), 400.0) * exp(-r * 11.0) * 0.4;
	vec3 f = sun_tint * (glow * flare_glow + spikes * flare_spikes);
	// Ghosts on the line from the sun through the centre: hexagons, soft edged, tinted by the
	// coatings (amber, teal, violet), brighter the nearer the sun is to the centre.
	vec2 axis = (sun_uv - vec2(0.5)) * asp;
	float centred = 1.0 - clamp(length(axis) * 1.1, 0.0, 1.0);
	vec2 c = (uv - vec2(0.5)) * asp;
	const float T[5] = float[5](-0.32, -0.62, -0.95, 0.42, -1.35);
	const float R[5] = float[5](0.035, 0.07, 0.025, 0.05, 0.11);
	const vec3 TINT[5] = vec3[5](vec3(1.0, 0.62, 0.28), vec3(0.35, 0.85, 0.75), vec3(0.75, 0.5, 1.0),
			vec3(0.6, 0.8, 1.0), vec3(1.0, 0.75, 0.45));
	vec3 g = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		vec2 q = c - axis * T[i];
		float h = hex_d(q, R[i]);
		float disc = 1.0 - smoothstep(-R[i] * 0.35, R[i] * 0.12, h);
		// A brighter rim, as a real ghost has.
		disc += (1.0 - smoothstep(0.0, R[i] * 0.10, abs(h))) * 0.5;
		g += TINT[i] * disc;
	}
	f += g * sun_tint * flare_ghosts * (0.35 + 0.65 * centred);
	// Shooting into the sun lifts the blacks over the whole frame.
	f += sun_tint * flare_veil * (0.4 + 0.6 * exp(-r * 2.5));
	return f * vis * flare_amount;
}

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Squashed slightly on Y so a wide frame does not darken the top and bottom more than the
	// sides.
	vec2 d = (uv - vec2(0.5)) * vec2(1.0, 0.88);
	float r2 = dot(d, d);
	// Fringing grows with the square of the distance from the centre, like a real lens.
	vec2 shift = (uv - vec2(0.5)) * fringe * r2 * 4.0;
	vec3 col;
	col.r = textureLod(screen_tex, uv + shift, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - shift, 0.0).b;
	float v = smoothstep(radius, radius + softness, sqrt(r2));
	col *= 1.0 - v * strength;
	if (flare_amount > 0.0) {
		// What the picture shows at the sun: one tap a few mips down, so a tower, a tree or a
		// cloud over the sun covers the flare as much as it covers the sun's neighbourhood.
		vec3 at_sun = textureLod(screen_tex, clamp(sun_uv, vec2(0.004), vec2(0.996)), 3.0).rgb;
		float vis = smoothstep(0.6, 0.94, max(at_sun.r, max(at_sun.g, at_sun.b)));
		if (vis > 0.0) {
			vec3 f = clamp(sun_flare(uv, vis), 0.0, 1.0);
			col = col + f - col * f;
		}
	}
	if (grain > 0.0 && lens_mode == 1) {
		float t = floor(TIME * grain_fps);
		vec2 px = floor(FRAGCOORD.xy);
		// Two hashes: a triangular distribution, closer to film than flat noise.
		float n = hash(px + vec2(t * 17.0, t * 31.0)) + hash(px + vec2(t * 23.0 + 91.0, t * 7.0 + 13.0)) - 1.0;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		float body = clamp(1.0 - luma, 0.0, 1.0);
		col += n * grain * grain_gain * (0.25 + 0.95 * body * body * (0.5 + luma));
	} else if (grain > 0.0) {
		float t = floor(TIME * grain_fps);
		float n = hash(floor(FRAGCOORD.xy) + vec2(t * 17.0, t * 31.0)) - 0.5;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		float mid = 4.0 * luma * (1.0 - luma);
		col += n * grain * (0.35 + 0.65 * clamp(mid, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
