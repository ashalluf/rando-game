// Forward+ review i (docs/HANDOFF.md "Forward+ review i"; FwdReviewI, FWD_REVIEW_I=0 the A/B).
//
// An unshaded blend_add shader that writes ALBEDO = colour x level with ALPHA 1 adds those numbers
// as they are: in DISPLAY numbers on Compatibility, in LINEAR HDR on Forward+, where the same 0.07
// displays ~0.29 - a faint shaft tuned on the opengl3 stills is a solid rod on the Mac (the jet's
// landing-light beams). fi_add() hands the display amount over on Forward+ (decoded, behind the
// switch); Compatibility is untouched. For amounts up to ~1, not HDR lamp cores.
//
// The includer is a spatial shader. Shader includes use // comments.

#ifndef FWD_REVIEW_I_DECLARED
#define FWD_REVIEW_I_DECLARED
global uniform float fwd_review_i;
#endif

vec3 fi_add(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	if (fwd_review_i < 0.5) {
		return c;
	}
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}

// The same for an HDR emitter whose soft tail was tuned as display numbers (the brush fire's glow
// card: flame cores at 3.2, a glow tail of a few %): the part up to 1 is handed over, what is over 1
// (the hot core) stays raw - continuous at 1, so a core keeps its bloom and a tail stays a tail.
vec3 fi_add_hdr(vec3 c) {
	c = max(c, vec3(0.0));
	return fi_add(min(c, vec3(1.0))) + max(c - vec3(1.0), vec3(0.0));
}
