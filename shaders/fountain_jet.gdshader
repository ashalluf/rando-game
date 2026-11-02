shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, unshaded;

// A fountain jet: a column of white water on a crossed pair of quads, streaks rising up it, a
// frothy crown at the top, fading at the edges and at the tip. UV: x across (0..1), y from the
// top (0) to the pool (1). Lit by the pool's own lights after dark.
//
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"

uniform float speed = 2.4;
uniform vec3 water : source_color = vec3(0.88, 0.93, 0.96);
uniform vec3 night_tint : source_color = vec3(0.6, 0.85, 1.0);

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float h = 1.0 - UV.y;
	// Narrow at the nozzle, spreading as it rises and breaks.
	float width = mix(0.35, 1.0, smoothstep(0.1, 1.0, h));
	float core = 1.0 - smoothstep(width * 0.55, width, x);
	float streak = 0.55 + 0.45 * sin((UV.x * 23.0) + (h - TIME * speed) * 17.0) * sin(UV.x * 51.0 - TIME * 3.0);
	float tip = 1.0 - smoothstep(0.82, 1.0, h);
	float a = core * (0.35 + 0.45 * streak) * tip;
	vec3 c = mix(water, night_tint * 1.4, lamp_factor * 0.6);
	// Unshaded, so it carries its own day/night level: white water in the sun, under-lit after dark.
	ALBEDO = c * mix(0.9, 1.1, streak) * mix(1.0, 0.7, night_factor);
	ALPHA = clamp(a, 0.0, 0.85);
}
