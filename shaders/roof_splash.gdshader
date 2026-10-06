shader_type spatial;
// One raindrop bursting on a car roof (RoofRain): an upright camera-facing card holding a crown
// of droplets thrown up and out and falling back, over a flattening ring. INSTANCE_CUSTOM.r is
// the splash's age 0..1. Water is mostly what it reflects, so its colour is the sky's horizon
// (`sky_tint`, raw on both renderers) dimmed at night and lifted by the street lamps.
// `sky_tint` holds sRGB numbers: it is decoded to linear here and the result handed over with
// cs_out(), so a splash is the same colour on Forward+ and Compatibility (written raw, Forward+
// took the sRGB numbers for linear light and drew every splash a stop too pale).
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform float night_factor;
global uniform float lamp_factor;

varying float age;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	age = INSTANCE_CUSTOM.r;
	vec3 to_cam = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 w = MODEL_MATRIX[3].xyz + right * VERTEX.x * sc.x + vec3(0.0, VERTEX.y * sc.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y); // x across, y up from the roof
	float u = clamp(age, 0.0, 1.0);
	float a = 0.0;
	// Eight droplets on ballistic arcs out of the impact.
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float side = (fi - 3.5) / 3.5;
		float spd = 0.6 + 0.5 * hash11(fi * 7.3 + floor(age * 0.0));
		vec2 p = vec2(side * u * 0.95, (spd * 3.2 * u - 3.0 * u * u) * 0.9);
		float d = length((q - p) * vec2(1.0, 0.7));
		a = max(a, 1.0 - smoothstep(0.035, 0.075, d));
	}
	// The ring on the roof, spreading and thinning.
	float ring = exp(-pow((abs(q.x) - u * 0.85) / 0.06, 2.0)) * (1.0 - smoothstep(0.0, 0.07, q.y));
	a = max(a, ring * 0.7);
	a *= (1.0 - u) * (1.0 - u * 0.3);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	vec3 col = mix(sky * 1.05 + vec3(0.012), sky * 0.12 + vec3(0.26, 0.15, 0.05) * 0.35 * lamp_factor, night_factor);
	ALBEDO = cs_out(col);
	ALPHA = clamp(a * 0.75, 0.0, 1.0);
}
