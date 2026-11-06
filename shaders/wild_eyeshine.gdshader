shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A wild animal's eyeshine (Rc5CoyoteNight, refcam5 coyote_night): the tapetum behind the retina
// throws the night's light back the way it came, so a coyote or a raccoon in the dark is first two
// points of light. One unit quad per eye on the head bone; the node's +Z is the eye's look. A
// camera-facing sprite at the eye's centre, pulled toward the camera past the eyeball, never drawn
// under `min_px` pixels (a coyote's eye at 20 m is under one), lit only after dark and only while
// the eye looks toward the camera. `tint` in DISPLAY numbers, added as Compatibility adds it (the
// Forward+ branch decodes it, house_glow.gdshader's rule: a broad add in linear HDR is a disc).

global uniform float lamp_factor;
uniform vec3 tint = vec3(0.86, 1.0, 0.52);
uniform float eye_r = 0.0115;
uniform float min_px = 1.7;
uniform float gain = 2.6;

varying float v_amp;

vec3 es_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 look = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float scale = length(MODEL_MATRIX[0].xyz);
	float depth = max(-c.z, 0.05);
	vec3 to_cam = normalize(-c.xyz);
	// The tapetum reflects back along the incoming light: strong only within a cone round the
	// eye's axis toward the viewer.
	float facing = smoothstep(0.2, 0.8, dot(look, to_cam));
	float px = 2.0 * depth / (abs(PROJECTION_MATRIX[1][1]) * 1080.0);
	float r = eye_r * scale;
	float s = max(r * 1.3, min_px * px);
	// What a pixel-sized sprite stands for: the eye's own size over the sprite's, kept above a
	// floor so a far pair still reads (two dim points, not nothing).
	float area = clamp((r * 1.3) / s, 0.35, 1.0);
	v_amp = lamp_factor * facing * gain * area;
	if (v_amp < 0.002) {
		POSITION = vec4(0.0);
	} else {
		vec3 p = c.xyz + to_cam * (r * 1.6) + vec3(VERTEX.xy * s * 2.2, 0.0);
		POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
	}
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0 * 2.2;
	// A hot core the eye's size and a soft glow round it.
	float core = 1.0 - smoothstep(0.35, 1.25, d);
	float glow = exp(-d * d * 0.5) * 0.4;
	float a = (core + glow) * v_amp;
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	ALBEDO = es_to_linear(tint * clamp(a, 0.0, 1.0)) * max(a, 1.0);
	ALPHA = 1.0;
#endif
}
