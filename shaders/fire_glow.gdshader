shader_type spatial;
// The brush fire on the ridge, seen from the city (SantaAnaFx): a wide billboard standing on the
// fire line, upright (it turns about Y only), additive. A broad soft glow on the hillside and,
// along its foot, a ragged line of flickering flame tongues. By day there is little of it (the
// smoke is what shows); after dark it is the orange glow that a ridge fire is from ten miles off.
// `level` carries the hour (script: lamp-style night ramp).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec3 flame_col = vec3(3.2, 1.25, 0.3);
uniform vec3 glow_col = vec3(0.55, 0.17, 0.04);
uniform float level = 0.0;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float vnoise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash11(i + seed), hash11(i + 1.0 + seed), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	// Upright billboard: face the camera about the vertical only.
	vec3 to_cam = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 w = MODEL_MATRIX[3].xyz + right * VERTEX.x * sc.x + vec3(0.0, VERTEX.y * sc.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0; // x across, y DOWN (UV.y 0 at the top)
	float up = 1.0 - UV.y;   // 0 at the foot, 1 at the top
	// The glow: wide and soft, brightest low down.
	// Faded to nothing on every edge of the card: an additive quad must never show its rectangle.
	float glow = exp(-up * 4.5) * (1.0 - smoothstep(0.2, 1.0, abs(q.x))) * (1.0 - smoothstep(0.35, 0.95, up))
		* smoothstep(0.0, 0.03, up);
	// The fire line: tongues along the foot, each its own height, flickering.
	float x = UV.x * 46.0;
	float h = 0.05 + 0.13 * vnoise1(x * 0.7 + TIME * 0.9) + 0.06 * vnoise1(x * 2.3 - TIME * 2.7);
	float run = smoothstep(0.15, 0.45, vnoise1(x * 0.18 + 5.0)) * (1.0 - smoothstep(0.75, 0.98, abs(q.x)));
	float tongue = (1.0 - smoothstep(h * 0.4, h, up)) * smoothstep(0.0, 0.015, up) * run;
	float flick = 0.75 + 0.25 * vnoise1(TIME * 7.0 + x);
	vec3 col = glow_col * glow * 0.55 + flame_col * tongue * flick;
	// NOT through cs_out(): added light on the Compatibility renderer lands on a display-space
	// buffer, where the sRGB curve would turn the glow's faint tail (0.03) into a bright 0.19 and
	// draw the card's rectangle. The same numbers on both renderers keep the tail a tail.
	ALBEDO = col * level;
	ALPHA = 1.0;
}
