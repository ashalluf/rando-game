shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The wingtip vapour (scripts/player/wingsuit_fx.gd): a camera-facing ribbon per wingtip. UV.x
// runs -1..1 across it, UV.y metres along it; COLOR is the brightness (dimmed at night by the
// script) and the opacity by age. Soft across, broken up along by two octaves of value noise
// that drift so the vortex seems to curl. Unshaded: vapour is lit by the sky it is in.

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float x = UV.x;
	float s = UV.y;
	float swirl = vnoise(s * 1.3 + TIME * 0.8) * 0.6 + vnoise(s * 4.1 - TIME * 1.7) * 0.4;
	float core = exp(-x * x * (3.0 + 2.0 * swirl));
	float edge = 1.0 - smoothstep(0.75, 1.0, abs(x));
	float a = COLOR.a * core * edge * mix(0.55, 1.15, swirl);
	ALBEDO = COLOR.rgb * vec3(0.97, 0.98, 1.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
