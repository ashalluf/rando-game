// The ambient occlusion a car or a prop leaves on the ground under it (ContactShadows,
// scripts/world/contact_shadows.gd): one flat quad per object, drawn as a darkening of what is
// already there (alpha-blended black: the ground times 1 - a), so it works the same on both
// renderers and costs one draw for every object near the camera.
//
// The quad's local frame is the object's footprint: x across, z along, UV 0..1 over the quad,
// which is the footprint grown by `margin` metres on every side. Per instance (half floats on
// the Compatibility renderer: sizes in metres, never positions):
//   INSTANCE_CUSTOM.r  footprint length (m)    .g  footprint width (m)
//   INSTANCE_CUSTOM.b  wheel track (m, 0 = a prop: no wheel blobs)
//   INSTANCE_CUSTOM.a  axle half spacing (m)
//   COLOR.r            margin: the quad is the footprint grown this much on every side (m)
//   COLOR.a            strength (0..1: distance fade, airborne fade, renderer gain)
// A MultiMesh's colours arrive raw on both renderers, so COLOR carries numbers, not a colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// The whole material's strength: ContactShadows sets it lower where SSAO already darkens.
uniform float gain = 1.0;
// Darkness of the body's occlusion at its centre, and of each wheel's contact patch.
uniform float body_dark = 0.62;
uniform float wheel_dark = 0.78;
// How far in from the footprint's edge the body occlusion reaches full darkness (m).
uniform float body_soft = 0.85;
// Wheel blob radius (m) across and along.
uniform vec2 wheel_size = vec2(0.34, 0.55);

varying vec4 v_info;
varying float v_strength;
varying float v_margin;

void vertex() {
	v_info = INSTANCE_CUSTOM;
	v_strength = COLOR.a * gain;
	v_margin = COLOR.r;
}

float rbox(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float margin = v_margin;
	float len = max(v_info.r, 0.1);
	float wid = max(v_info.g, 0.1);
	// Metres from the footprint's centre: x across, y along.
	vec2 p = (UV - 0.5) * vec2(wid + 2.0 * margin, len + 2.0 * margin);
	// Signed distance to the footprint (rounded: no car is a box).
	float d = rbox(p, vec2(wid, len) * 0.5, min(wid, len) * 0.22);
	// Occlusion: full well inside, falling off to nothing `margin` outside - the shape of the
	// sky the body hides from a point on the ground.
	float body = 1.0 - smoothstep(-min(body_soft, 0.45 * min(wid, len)), margin, d);
	body *= body * body_dark;
	float wheels = 0.0;
	if (v_info.b > 0.01) {
		vec2 c = vec2(v_info.b * 0.5, v_info.a);
		vec2 w = abs(p) - c;
		w /= wheel_size;
		wheels = (1.0 - smoothstep(0.0, 1.0, length(w))) * wheel_dark;
	}
	float a = max(body, wheels) * v_strength;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(a, 0.0, 0.95);
}
