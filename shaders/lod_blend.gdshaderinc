// A screen-door crossfade between a near body and its far twin (CarLodBlend, wave 5 "lod-pops").
// lod_blend = (lo, hi, side): the near body is kept where its visibility - 1 at or nearer than
// lo, 0 at or past hi, smoothstep between, from the camera to the node's origin - beats the
// pixel's interleaved-gradient-noise threshold; the far twin (side 1) is kept exactly where the
// near one is not, so the pair is drawn once per pixel, opaque, with no hole and no double. It is
// StandardMaterial3D's OBJECT_DITHER distance fade, line for line (min = hi, max = lo), so the
// glTF's own part materials faded that way take the same pixels. Off (one branch) while hi <= 0,
// and never in a shadow pass (the shadow twins overlap instead).
uniform vec3 lod_blend = vec3(0.0);

bool lod_blend_cut(vec2 frag, mat4 view, mat4 model, bool shadow) {
	if (lod_blend.y <= 0.0 || shadow) {
		return false;
	}
	float d = length(view * model[3]);
	float t = clamp((d - lod_blend.y) / (lod_blend.x - lod_blend.y), 0.0, 1.0);
	float fade = t * t * (3.0 - 2.0 * t);
	const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	bool near_keeps = !(fade < 0.001 || fade < fract(magic.z * fract(dot(frag, magic.xy))));
	return lod_blend.z > 0.5 ? near_keeps : !near_keeps;
}
