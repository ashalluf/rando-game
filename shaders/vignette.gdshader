shader_type canvas_item;

// A full-screen darkening toward the corners. Every camera lens does this, and every film and
// game leans on it: it keeps the eye in the middle of the frame and stops the picture looking
// like a flat render. Kept subtle on purpose - if you can see it, it is too strong.

uniform float strength : hint_range(0.0, 1.0) = 0.30;
// Where the falloff starts, as a fraction of half the screen diagonal, and how soft it is.
uniform float radius : hint_range(0.1, 1.2) = 0.46;
uniform float softness : hint_range(0.05, 2.0) = 0.85;

void fragment() {
	// Squashed slightly on Y so a wide frame does not darken the top and bottom more than the
	// sides.
	vec2 d = (SCREEN_UV - vec2(0.5)) * vec2(1.0, 0.88);
	float v = smoothstep(radius, radius + softness, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
