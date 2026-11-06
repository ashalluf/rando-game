// Forward+ review h (docs/HANDOFF.md "Forward+ review h"; FwdReviewH, FWD_REVIEW_H=0 the A/B).
//
// A shader that works in the renderer's own space (display numbers on Compatibility, linear on
// Forward+: `to_lit()` / `col()` colours) and emits `colour x level`, where `level` is a light's
// strength it worked out itself (a falloff from a flare or a floodlight, 0..~1.5), left the level
// raw. Compatibility then draws colour x level in display numbers; Forward+ draws
// encode(decode(colour) x level) ~ colour x level^0.45 - a surface lit at 10 % of a lamp's centre
// showed ~35 % on the Mac: the refinery's tanks 150 m from a flare glowed orange all over, where
// the opengl3 stills (what the light was tuned on) show a warm rim. fh_level() hands the level
// over in the renderer's space too (decoded on Forward+), so the product displays as tuned.
//
// The includer is a spatial shader. Shader includes use // comments.

#ifndef FWD_REVIEW_H_DECLARED
#define FWD_REVIEW_H_DECLARED
global uniform float fwd_review_h;
#endif

float fh_level(float x) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return x;
#else
	if (fwd_review_h < 0.5) {
		return x;
	}
	x = max(x, 0.0);
	return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
#endif
}

// A colour the shader EMITS as plain numbers that were judged on Compatibility, where they display
// as written (industrial_walls.gdshader's glass mirror: on Forward+ it read as linear and the panes
// were pale sheets of sky). Decoded on Forward+ (behind the switch), as written on Compatibility.
// For colours (0..1), not HDR lamps.
vec3 fh_display(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	if (fwd_review_h < 0.5) {
		return c;
	}
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}
