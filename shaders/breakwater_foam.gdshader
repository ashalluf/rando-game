shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;

// The white water round the breakwater's foot (LighthouseKit): a ribbon along each waterline,
// UV.x metres along the breakwater, UV.y 0 at the stones to 1 offshore. Swells surge up the
// armour and drain back, so the foam is a band that pulses in and out with the waves (a few
// seconds a surge, phased along the breakwater so it runs along it), torn into lace by noise,
// thickest against the stones. Lit, so it is grey at night. Alpha blended.

global uniform float wave_scale;

uniform float surge_period = 7.5;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float along = UV.x;
	float across = UV.y;
	float t = TIME / surge_period + along * 0.012;
	float surge = 0.5 + 0.5 * sin(t * 6.2831853);
	float reach = mix(0.25, 0.85, surge) * (0.7 + 0.3 * clamp(wave_scale, 0.0, 2.0));
	vec2 p = vec2(along * 0.35, across * 4.0 - TIME * 0.15);
	float lace = vnoise(p * 2.0) * 0.55 + vnoise(p * 6.5 + 3.0) * 0.3 + vnoise(p * 17.0) * 0.15;
	float band = 1.0 - smoothstep(reach * 0.6, reach, across + (lace - 0.5) * 0.35);
	float a = band * smoothstep(0.32, 0.62, lace + (1.0 - across) * 0.35);
	ALBEDO = vec3(0.86, 0.88, 0.88);
	ROUGHNESS = 0.6;
	ALPHA = clamp(a, 0.0, 1.0) * 0.85;
}
