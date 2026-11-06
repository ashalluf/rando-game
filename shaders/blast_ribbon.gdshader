shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

// The smoke trails off burning debris (BlastDebris._ribbons(), fleet wave 8 "explosions-4",
// round 14). As a flat-alpha band every trail had two hard edges, and from inside a blast's
// smoke (5 m) its quads drew as sharp translucent arcs across the frame. UV.x runs 0..1 across
// the band, UV.y metres along it: a soft round profile across, value noise eating its
// edges along the run, so a trail reads as a torn wisp. COLOR is the linear albedo and alpha the
// script worked out (vertex colours arrive raw on both renderers: linear numbers, cs_out()).

#include "res://shaders/color_space.gdshaderinc"

float rb_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rb_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rb_hash(i), rb_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rb_hash(i + vec2(0.0, 1.0)), rb_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float prof = 1.0 - u * u;
	prof *= prof;
	// Billows along the run (UV.y in metres), torn harder toward the band's edges.
	float n = rb_noise(vec2(UV.x * 2.5, UV.y * 1.3)) * 0.65 + rb_noise(vec2(UV.x * 6.0, UV.y * 3.1 + 7.0)) * 0.35;
	float a = COLOR.a * prof * smoothstep(0.25 + 0.35 * abs(u), 0.75, n);
	if (a < 0.002) {
		discard;
	}
	ALBEDO = cs_out(COLOR.rgb);
	ALPHA = clamp(a * 1.6, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
