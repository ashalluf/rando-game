shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

// The shock ring on the ground (Blast4, fleet wave 5 "explosions-4", round 11): dust and grit
// lifted off the road by the wave as it races out, a pale ragged band that runs out to `reach`
// metres in its first half second and hangs there fading - from a few metres it is the dust
// roll's job; from the air (150 m up) it is the thing that reads: the blast's footprint on the
// street. One quad laid on the ground, `age` driven by a tween. Colours linear on both renderers
// (color_space.gdshaderinc), lit by hand (the sun's colour and the sky's), so it reads at any hour.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform float reach = 30.0;
uniform float age = 0.0;
uniform float seed = 0.0;
uniform vec3 dust = vec3(0.32, 0.29, 0.25);
global uniform float night_factor;
global uniform vec4 sky_tint;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0; // -1..1 across the quad (the quad is 2 reach across)
	float r = length(q);
	float ang = atan(q.y, q.x);
	// The front: fast out, slowing (a shock in air loses speed with distance).
	float front = 1.0 - exp(-age / 0.16);
	float rag = texture(noise3d, vec3(cos(ang) * 0.35 + seed, sin(ang) * 0.35, age * 0.05)).r;
	float fine = texture(noise3d, vec3(q * 1.6 + seed, 0.4 + age * 0.08)).r;
	float rf = front * (0.88 + 0.24 * rag);
	float width = 0.05 + 0.22 * front;
	// A band behind the front, thickest just behind it, thinning toward the middle.
	float band = smoothstep(rf - width, rf - width * 0.3, r) * (1.0 - smoothstep(rf - width * 0.15, rf + 0.02, r));
	float inner = (1.0 - smoothstep(0.0, rf, r)) * 0.35;
	float a = max(band, inner * band + inner * 0.5) * (0.55 + 0.45 * fine);
	a *= (1.0 - smoothstep(0.6, 5.5, age)) * smoothstep(0.0, 0.03, age);
	a *= 1.0 - smoothstep(0.94, 1.0, r);
	if (a < 0.003) {
		discard;
	}
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	vec3 light = mix(vec3(1.25, 1.18, 1.05), sky * 0.25 + vec3(0.02), night_factor);
	ALBEDO = cs_out(dust * light * (0.75 + 0.5 * fine));
	ALPHA = clamp(a * 0.85, 0.0, 1.0);
}
