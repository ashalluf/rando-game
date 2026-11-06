shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// The pier wheel's LEDs seen from afar, and the light they throw into the air round it
// (PierNight, scripts/world/pier_night.gd). Two quads in the wheel's plane, one over each face's
// LEDs (just proud of them), the wheel node's own space (the hub at `hub`), turning with the wheel
// by the same omega the wheel's vertex stage uses.
//
// The LED strips are 13 cm wide: from the beach (100-300 m) they are a fifth of a pixel and the
// Compatibility renderer, with no MSAA, drew the wheel as its white steel with a few aliased
// specks of colour. Here every spoke strip and both rings are drawn ANALYTICALLY at their true
// place and pattern (pier_led.gdshaderinc, the same functions the LEDs run), each at least
// `min_px` pixels wide with its light spread over that width (the strip's own energy, not more),
// faded in only once the real strips are under a couple of pixels (`far_px`). Over that, a soft
// glow of the wheel's mean colour in the air round it (worked out in the vertex stage from the
// pattern), zero at the quad's edge (an additive tail on Forward+ draws the quad). Everything
// follows lamp_factor; by day the quads collapse in the vertex stage.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/night_halo.gdshaderinc"
#include "res://shaders/pier_led.gdshaderinc"

global uniform float lamp_factor;

uniform vec3 hub = vec3(0.0, 16.8, 0.0);
uniform float omega = 0.0419;
uniform float radius = 13.0;
uniform float inner = 11.6;
uniform float spokes = 20.0;
uniform float pattern_seconds = 14.0;
// The LEDs' energy (pier_park.gdshader's led_energy) and the dots' average lit share.
uniform float led_energy = 4.5;
uniform float dot_share = 0.55;
// A strip's real width (m), the least it is drawn across (pixels), and the metres a pixel spans
// where the drawn strips take over from the real ones (fully by `far_px` x 2.5).
uniform float strip_w = 0.13;
uniform float min_px = 1.6;
uniform float far_px = 0.045;
// The air's glow: strength (linear, added) and its fall-off past the rim, in radii.
uniform float glow_gain = 0.05;
uniform float glow_reach = 0.2;
// Seconds added to TIME (stills: the wheel turned and its patterns run on, as pier_park's own).
uniform float time_offset = 0.0;

varying vec3 v_local;
varying vec3 v_mean;
varying float v_lit;

void vertex() {
	float lit = smoothstep(0.08, 0.6, lamp_factor);
	v_local = VERTEX;
	v_lit = lit;
	if (lit < 0.002) {
		VERTEX = vec3(0.0);
	}
	// The wheel's mean colour now: eight spokes at three radii.
	vec3 m = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float s = float(i) * spokes / 8.0;
		for (int j = 0; j < 3; j++) {
			m += led_wheel(s, 0.3 + 0.3 * float(j), TIME + time_offset, spokes, pattern_seconds);
		}
	}
	v_mean = m / 24.0;
}

// A line `d` metres off its centre: the strip's light spread over at least min_px pixels.
float strip(float d, float mpp) {
	float w = max(strip_w * 0.5, min_px * mpp * 0.5);
	// A spread strip keeps more than its share of the light: the LEDs bloom in the lens and the
	// air (the square root, between conserving it and not).
	return (1.0 - smoothstep(w * 0.6, w, d)) * sqrt(min(strip_w * 0.5 / w, 1.0));
}

void fragment() {
	vec2 p = v_local.xy - hub.xy;
	float r = length(p);
	float mpp = max(length(vec2(fwidth(v_local.x), fwidth(v_local.y))) * 0.7, 1e-4);
	float t = TIME + time_offset;
	float far_k = smoothstep(far_px, far_px * 2.5, mpp);
	vec3 emit = vec3(0.0);
	if (far_k > 0.001 && r < radius + 0.5) {
		float step_a = TAU / spokes;
		float a = atan(p.y, p.x) - omega * t;
		float k = round(a / step_a);
		float dperp = abs(sin(a - k * step_a)) * r;
		float s = mod(k, spokes);
		float along = smoothstep(1.45, 1.75, r) * (1.0 - smoothstep(inner, inner + 0.15, r));
		vec3 c = led_wheel(s, r / radius, t, spokes, pattern_seconds) * strip(dperp, mpp) * along;
		float sc = mod(a / step_a, spokes);
		c += led_wheel(sc, 1.0, t, spokes, pattern_seconds) * strip(abs(r - radius), mpp);
		c += led_wheel(sc, inner / radius, t, spokes, pattern_seconds) * strip(abs(r - inner), mpp);
		emit = c * led_energy * dot_share * far_k;
	}
	// The air round the wheel: a faint fill inside, falling off past the rim, zero at the edge.
	float inside = 0.3 + 0.7 * smoothstep(0.0, radius, r);
	float outside = exp(-max(r - radius, 0.0) / (glow_reach * radius));
	float edge = 1.0 - smoothstep(radius * 1.3, radius * 1.55, r);
	float haze = mix(0.7, 1.6, clamp(night_atmos.x, 0.0, 1.0));
	// Two quads, one each face: each carries half the air's glow.
	emit += v_mean * glow_gain * 0.5 * haze * (r < radius ? inside : outside) * edge;
	emit *= v_lit * nh_far(length(VERTEX));
	ALBEDO = cs_out(emit);
}
