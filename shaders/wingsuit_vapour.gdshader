shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The wingtip vapour (scripts/player/wingsuit_fx.gd): a camera-facing ribbon per wingtip. UV.x
// runs -1..1 across it, UV.y metres along it; COLOR is the brightness (dimmed at night by the
// script) and the opacity by age. Soft across, broken up along by two octaves of value noise
// that drift so the vortex seems to curl. Unshaded: vapour is lit by the sky it is in.
// `look` 1 (rc5-wingsuit-golden; WingsuitFx.look2): the mist takes the sky's colour and the sun's,
// brightest looking toward the sun (cloud droplets scatter forward), so at golden hour it is a warm
// streak, not a white one; the core thinner and the edges wispier. 0: the old white ribbon.
#include "res://shaders/color_space.gdshaderinc"

uniform float look = 0.0;
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform vec3 tree_sun;

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
	if (look > 0.5) {
		vec3 look_dir = -normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 sd = normalize(sun_direction);
		float mu = max(dot(look_dir, sd), 0.0);
		float phase = 0.35 + 0.65 * mu * mu + 2.2 * pow(mu, 10.0);
		vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
		vec3 sun = min(tree_sun, vec3(2.5));
		vec3 col = sky * 0.75 + sun * 0.38 * phase;
		// Brightness (the script's night dimming) on top; never brighter than a lit cloud.
		col = min(col * COLOR.r, vec3(1.6));
		ALBEDO = cs_out(col);
		// A thin twisted core, wisps at the edge.
		float wisp = vnoise(s * 2.3 + x * 3.1 - TIME * 1.1);
		a = COLOR.a * (core * 0.85 + 0.25 * wisp * (1.0 - core)) * edge * mix(0.6, 1.2, swirl);
	}
	ALPHA = clamp(a, 0.0, 1.0);
}
