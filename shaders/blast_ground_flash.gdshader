shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded, fog_disabled;

// The ground flash (Blast4, fleet wave 8 "explosions-4", round 13): from 150 m up the fireball
// is a 9 m ball the cap hides at once, so a blast's first frames read as a small pale blob. Real
// aerial footage reads the flash on the GROUND first: the street lit white-orange round the burst
// for a few frames, a scorching glow that shrinks into the crater's embers. One quad laid on the
// ground beside the shock ring, `age` from its tween. Additive and fog-free (CLAUDE.md, additive
// shaders and fog), reaching exactly zero at the quad's edge. Linear on both renderers.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler3D noise3d : filter_linear, repeat_enable;
uniform float age = 0.0;
uniform float seed = 0.0;
uniform float gain = 1.0;
// The air's view only: from the street the blast's OmniLight already lights the road, and this
// quad added over it at a grazing look painted the whole road a flat cream.
uniform float air_near = 25.0;
uniform float air_far = 60.0;
global uniform float night_factor;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float rag = texture(noise3d, vec3(cos(ang) * 0.4 + seed, sin(ang) * 0.4, 0.2)).r;
	float fine = texture(noise3d, vec3(q * 2.3 + seed, 0.7)).r;
	// The flash: white-hot, spreading over the first 60 ms, gone by ~0.4 s.
	float flash = exp(-age / 0.09) * smoothstep(0.0, 0.015, age);
	float spread = mix(0.45, 1.0, 1.0 - exp(-age / 0.05)) * (0.85 + 0.3 * rag);
	float disc = 1.0 - smoothstep(0.0, spread, r);
	disc *= disc;
	// The glow under the burning core: orange, shrinking toward the middle over 3 s.
	float glow = exp(-age / 1.1) * (1.0 - smoothstep(0.0, 0.42 * (0.8 + 0.4 * rag), r)) * (0.6 + 0.8 * fine);
	vec3 hot = vec3(1.0, 0.82, 0.55) * 7.0 * flash * disc;
	vec3 ember = vec3(1.0, 0.36, 0.08) * 1.6 * glow;
	vec3 c = (hot + ember) * gain * mix(1.0, 1.6, night_factor);
	// Exactly zero at the quad's edge: an additive tail draws the quad.
	c *= 1.0 - smoothstep(0.8, 0.98, r);
	c *= smoothstep(air_near, air_far, length(VERTEX)) * smoothstep(0.15, 0.4, abs(dot(NORMAL, VIEW)));
	if (max(c.r, max(c.g, c.b)) < 0.002) {
		discard;
	}
	ALBEDO = cs_out(c);
}
