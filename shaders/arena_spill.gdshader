shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The light a giant LED screen throws on the plaza in front of it after dark (ArenaNight,
// rc5-arena-night). STARLIGHT PLAZA's screen wall glowed on its own and lit nothing: at 21:00 the
// paving under 200 m2 of screens was as dark as a car park. A flat quad on the ground in front of
// each screen, its colour the screen's CURRENT slide worked out exactly as led_screen.gdshader
// picks it (the same slot, the same two hues from lm_hash21, the same wipe), so the pool changes
// colour with the picture. Added in display numbers on both renderers (fwd-review-e: a broad pool
// added in linear HDR is a flat disc on Forward+), with a coverage alpha so the fog adds its colour
// only where there is light (additive_fog.gdshaderinc).
// UV: x across the quad (0..1), y from the wall (0) out to the quad's far edge (1).
// Shader files use // comments, never #.

#include "res://shaders/landmark_common.gdshaderinc"
#include "res://shaders/additive_fog.gdshaderinc"


// The screen's own numbers (LedScreen.material(): seed, slide_seconds, the atlas' slide count).
uniform float seed = 0.0;
uniform float slide_seconds = 6.0;
uniform int slide_count = 12;
// The screen's half width as a share of the quad's half width (full light inside it).
uniform float screen_share = 0.7;
uniform float strength = 0.55;
// A floor under the slide's colour: a screen's picture is mostly bright, never black.
uniform float base_light = 0.35;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

vec3 as_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float clock = TIME + seed * 17.0;
	float slot = floor(clock / slide_seconds);
	// int() in the screen's shader: a truncation (seed x 5 is fractional for most screens).
	float k = floor(mod(slot + seed * 5.0, float(slide_count)));
	vec3 c1 = hue(lm_hash21(vec2(k, seed + 1.0)));
	vec3 c2 = mix(hue(lm_hash21(vec2(k + 7.0, seed + 2.0))), vec3(1.0), 0.25);
	float since = clock - slot * slide_seconds;
	float wipe = mix(0.12, 1.0, smoothstep(0.0, 0.5, since));
	vec3 col = mix(vec3(base_light), (c1 + c2) * 0.5, 0.75) * wipe;
	// Across: full in front of the screen, falling off past its ends.
	float ax = abs(UV.x - 0.5) * 2.0;
	float across = 1.0 - smoothstep(screen_share, 1.0, ax);
	// Out from the wall: little right at its foot (the screen is 6 m up), a broad peak a few metres
	// out, then a long tail, reaching zero at the quad's edge.
	float v = clamp(UV.y, 0.0, 1.0);
	float out_k = smoothstep(0.0, 0.06, v) * pow(1.0 - v, 1.7);
	float a = across * out_k * strength * lamp_factor;
	vec3 disp = clamp(col * a, vec3(0.0), vec3(1.0));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 o = af_cover(disp);
#else
	vec4 o = af_cover(as_linear(disp));
#endif
	ALBEDO = o.rgb;
	ALPHA = o.a;
}
