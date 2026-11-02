shader_type spatial;
render_mode cull_disabled;

// A trampoline's safety net (BackyardKit._trampoline): a knotted polyester mesh, 4 cm squares,
// cut out where the threads are not. Under a pixel the threads blur to their cover (about a
// third), dithered, so from across a yard the net is a dark veil and never a moire.
// UV is metres round and up the net; COLOR.rgb the thread colour (sRGB).

#include "res://shaders/color_space.gdshaderinc"

uniform float cell = 0.045;
uniform float thread = 0.12;
/// Chain-link: the squares turned 45 degrees (the dog run).
uniform bool diamond = false;

void fragment() {
	vec2 uvd = diamond ? vec2(UV.x + UV.y, UV.x - UV.y) * 0.7071 : UV;
	vec2 g = uvd / cell;
	vec2 fw = fwidth(g);
	float px = max(fw.x, fw.y);
	vec2 f = abs(fract(g) - 0.5);
	float t = max(step(0.5 - thread, f.x), step(0.5 - thread, f.y));
	float cover = 1.0 - (1.0 - 2.0 * thread) * (1.0 - 2.0 * thread);
	float k = mix(t, cover, smoothstep(0.35, 0.9, px));
	// Dither the blurred share against a screen-space pattern (TAA resolves it on the Mac).
	vec2 sp = floor(FRAGCOORD.xy);
	float dither = fract(dot(sp, vec2(0.7548777, 0.5698403)) + 0.5);
	if (k < dither) {
		discard;
	}
	ALBEDO = cs_out(cs_srgb_to_linear(COLOR.rgb));
	ROUGHNESS = diamond ? 0.45 : 0.8;
	METALLIC = diamond ? 0.7 : 0.0;
}
