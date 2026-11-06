shader_type spatial;
render_mode cull_back;

// The LED face of a changeable message sign on a freeway gantry (FreewayIncidents /
// FreewayIncidentKit): a matrix of amber LEDs behind dark glass, one texel of `page_a` / `page_b`
// a LED (5 x 7 glyphs, LedScreen.GLYPHS). Two pages alternate (`page_seconds` each, a short dark
// gap between, as the real signs do). Round LEDs anti-aliased by their footprint; past a pixel a
// LED the dots merge into the glow they average to. Lit enough to read by day, a glow at night.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

uniform sampler2D page_a : filter_nearest, repeat_disable;
uniform sampler2D page_b : filter_nearest, repeat_disable;
uniform vec2 cells = vec2(111.0, 31.0);
uniform float two_pages = 0.0;
uniform float page_seconds = 3.2;
uniform float gap_seconds = 0.35;
// Linear colours.
uniform vec3 led_color = vec3(1.0, 0.50, 0.05);
uniform float led_day = 2.6;
uniform float led_night = 1.3;
uniform float lit = 1.0;

void fragment() {
	vec2 uv = clamp(vec2(UV.x, UV.y), vec2(0.0), vec2(0.9999));
	vec2 c = uv * cells;
	vec2 cell = floor(c);
	vec2 f = fract(c) - 0.5;
	float cycle = page_seconds * 2.0 + gap_seconds * 2.0;
	float ph = mod(TIME, cycle);
	float on_a = texture(page_a, (cell + 0.5) / cells).r;
	float on_b = texture(page_b, (cell + 0.5) / cells).r;
	float on = on_a;
	if (two_pages > 0.5) {
		if (ph < page_seconds) {
			on = on_a;
		} else if (ph < page_seconds + gap_seconds) {
			on = 0.0;
		} else if (ph < page_seconds * 2.0 + gap_seconds) {
			on = on_b;
		} else {
			on = 0.0;
		}
	}
	float w = max(max(fwidth(c.x), fwidth(c.y)), 1e-4);
	float d = length(f);
	float dot_m = 1.0 - smoothstep(0.34 - w, 0.34 + w, d);
	float far = smoothstep(0.35, 0.9, w);
	dot_m = mix(dot_m, 0.36, far);
	float energy = mix(led_day, led_night, night_factor) * lit;
	vec3 glass = vec3(0.008, 0.008, 0.010);
	ALBEDO = cs_out(glass);
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	// An unlit LED is a dull dot you can just make out.
	EMISSION = cs_out(led_color * (on * dot_m * energy + 0.010 * dot_m * lit));
}
