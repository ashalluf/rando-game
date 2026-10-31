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
	if (grain > 0.0) {
		float t = floor(TIME * grain_fps);
		float n = hash(floor(FRAGCOORD.xy) + vec2(t * 17.0, t * 31.0)) - 0.5;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		float mid = 4.0 * luma * (1.0 - luma);
		col += n * grain * (0.35 + 0.65 * clamp(mid, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
