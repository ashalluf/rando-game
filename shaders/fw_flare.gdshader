shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// A burning road flare's light (FreewayIncidents' flare line behind a stalled car's patrol car):
// `mode` 0 the glow, a quad turned to the camera and never drawn smaller than `min_px` pixels so a
// line of flares reads from far down the freeway; `mode` 1 its red pool on the deck, a flat quad.
// Both flicker from TIME, phased by the flare's world position. Linear colours (plain uniforms),
// written out through cs_out(): the red is held to a tenth green or AgX turns it salmon.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform float mode = 0.0;
uniform float size = 0.42;
uniform float min_px = 3.0;
uniform vec2 viewport_px = vec2(1280.0, 720.0);
uniform vec3 core_color = vec3(3.6, 1.05, 0.85);
uniform vec3 halo_color = vec3(2.4, 0.22, 0.14);
uniform float day_gain = 0.55;
uniform float night_gain = 1.0;
uniform float pool_gain = 0.55;

varying float v_flick;

float h11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = h11(wp.x * 0.37 + wp.z * 1.13) * 40.0;
	float t = TIME * 13.0 + ph;
	// Two beating rates and a slow breath: a flare sputters, it does not strobe.
	v_flick = 0.78 + 0.12 * sin(t) + 0.07 * sin(t * 2.31 + 1.7) + 0.06 * sin(TIME * 1.7 + ph);
	if (mode < 0.5) {
		vec4 vp = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
		float dist = max(-vp.z, 0.05);
		// Metres a pixel spans at that distance (the projection's y scale; abs: negative on
		// Compatibility).
		float px = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * max(viewport_px.y, 1.0));
		float s = max(size, px * min_px) * (0.85 + 0.15 * v_flick);
		vp.xy += VERTEX.xy * s;
		POSITION = PROJECTION_MATRIX * vp;
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float gain = mix(day_gain, night_gain, clamp(lamp_factor, 0.0, 1.0)) * v_flick;
	vec3 col;
	if (mode < 0.5) {
		// A white-hot point in a tight red halo: a flare reads as a spark, not a ball.
		float core = exp(-r * r * 60.0);
		float halo = exp(-r * r * 9.0) * (1.0 - smoothstep(0.7, 1.0, r));
		col = core_color * core * 1.6 + halo_color * halo * 0.7;
	} else {
		float pool = exp(-r * r * 3.2) * (1.0 - smoothstep(0.8, 1.0, r));
		col = halo_color * pool * pool_gain * mix(0.35, 1.0, clamp(lamp_factor, 0.0, 1.0));
	}
	ALBEDO = cs_out(col * gain);
}
