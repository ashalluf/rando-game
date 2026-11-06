// A lightning bolt (StormDrama, scripts/world/storm_drama.gd): one ribbon mesh a strike, built
// facing the camera, the channel's core in UV.x (-1..1 across) and how far down the bolt in UV.y.
// Additive and fog-free: a storm's fog hides a strike 2 km out entirely, and the channel is the
// brightest thing in the sky for the frame it is there. `level` is the flash's flicker.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://shaders/color_space.gdshaderinc"

uniform float level = 0.0;
// How hot the core is (linear, HDR on Forward+: it blooms).
uniform float energy = 3.0;
// The halo's share of the brightness, and how wide it is next to the core.
uniform float halo = 0.35;
uniform vec3 tint = vec3(0.74, 0.80, 1.0);

void fragment() {
	float x = abs(UV.x);
	float core = exp(-x * x * 26.0);
	float glow = exp(-x * x * 3.2) * halo;
	// A branch (UV2.x) is dimmer and fades toward its tip.
	float tip = mix(1.0, 1.0 - UV.y * 0.8, UV2.x);
	float b = (core + glow) * tip * level * mix(1.0, 0.55, UV2.x);
	ALBEDO = cs_out(tint * b * energy);
	// Additive: zero at the ribbon's edge (a tail there draws the quad on Forward+).
	ALBEDO *= smoothstep(1.0, 0.85, x);
}
