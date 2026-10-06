// Caution tape strung round a news scene (NewsKit.tape_mesh): safety yellow polyethylene with
// black block capitals, a satin sheen, fluttering in the wind. UV.x metres along the tape (the
// print repeats every `print_len` m), UV.y across it (0..1); UV2.x how far into its span (0..1),
// so the flutter is pinned at the posts. Drawn from both sides.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;

uniform sampler2D print_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
// Metres one repeat of the print covers.
uniform float print_len = 0.84;
// The tape's yellow and the ink, linear.
uniform vec3 tape_color = vec3(0.92, 0.62, 0.012);
uniform vec3 ink_color = vec3(0.012, 0.012, 0.012);
// Flutter: metres at mid-span in a breeze, and how fast.
uniform float flutter = 0.035;
uniform float flutter_rate = 7.0;

void vertex() {
	float span = UV2.x;
	float pin = sin(clamp(span, 0.0, 1.0) * PI);
	float gust = 0.35 + clamp(wind_factor, 0.0, 3.0);
	float t = TIME * flutter_rate + UV.x * 2.3 + UV2.y * 1.7;
	// Sideways (the tape's own normal) and a little up and down, more on the trailing edge.
	float w = (sin(t) * 0.7 + sin(t * 2.31 + 1.3) * 0.3) * flutter * gust * pin;
	VERTEX += NORMAL * w * (0.6 + 0.8 * UV.y);
	VERTEX.y += sin(t * 0.7 + 0.4) * flutter * 0.4 * gust * pin;
}

void fragment() {
	vec2 puv = vec2(UV.x / print_len, UV.y);
	// The print sits in the middle 80 % of the tape's width.
	vec2 tuv = vec2(puv.x, (puv.y - 0.1) / 0.8);
	float ink = (tuv.y > 0.0 && tuv.y < 1.0) ? texture(print_tex, tuv).r : 0.0;
	vec3 col = mix(tape_color, ink_color, ink);
	// A thin darker edge line on both edges, printed like the real thing.
	float edge = smoothstep(0.06, 0.03, min(UV.y, 1.0 - UV.y));
	col = mix(col, tape_color * 0.55, edge * (1.0 - ink));
	ALBEDO = cs_out(col);
	ROUGHNESS = 0.38;
	SPECULAR = 0.45;
	BACKLIGHT = cs_out(col * 0.35);
}
