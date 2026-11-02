// Near-camera dither (rc2-hero-foot, 2026-11-01; CameraFade, scripts/world/camera_fade.gd).
// The on-foot camera sits 6.5 m behind the hero and its spring arm only collides with the world
// layer, so on a tree-lined pavement it passes through street-tree crowns and trunks, which have
// no collision: half the frame was leaves or bark. Like every 2026 third-person game, what comes
// within cf_far metres of the camera dithers out, gone inside cf_near. cf_far 0 (the default,
// CAMERA_FADE=0) is the shader as it was. Never in a directional shadow pass (orthographic):
// the shadow keeps the whole tree.
uniform float cf_near : hint_range(0.0, 10.0) = 0.0;
uniform float cf_far : hint_range(0.0, 10.0) = 0.0;

bool cf_gone(vec3 view_vertex, vec2 frag, mat4 proj) {
	if (cf_far <= 0.0 || proj[3][3] > 0.5) {
		return false;
	}
	float d = length(view_vertex);
	if (d >= cf_far) {
		return false;
	}
	float keep = smoothstep(cf_near, cf_far, d);
	// Interleaved gradient noise: an even dither TAA resolves (Forward+); a fine grain elsewhere.
	float n = fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
	return keep <= n;
}
