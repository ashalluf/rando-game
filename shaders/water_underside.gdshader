shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

// The underside of the water's surface, seen from below (Swim): a plane at the surface over the
// camera, drawn only while the camera is under it (the sea, the marina and the lake draw their
// surfaces one-sided, from above). Straight up through it is Snell's window - the whole sky
// squeezed into a bright disc of 48.6 degrees half-angle round the vertical, rippling - and past
// it the surface is a mirror of the dark water below (total internal reflection). Distance veils
// it in the water's colour, as the underwater pass veils everything else.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform float night_factor;

uniform vec3 deep_color = vec3(0.004, 0.035, 0.045);
uniform vec3 fog_color = vec3(0.012, 0.09, 0.10);
uniform float window_gain = 1.6;
uniform float fog_per_m = 0.0;
uniform vec2 world_offset = vec2(0.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 wdir = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz + world_offset;
	float t = TIME;
	// Ripples tilt the window's edge and break the light into a moving net.
	float r = vnoise(p * 0.9 + vec2(t * 0.5, t * 0.3)) + 0.5 * vnoise(p * 2.3 - vec2(t * 0.8, -t * 0.6));
	float up = wdir.y + (r - 0.75) * 0.06;
	float window = smoothstep(0.62, 0.70, up);
	float day = 1.0 - 0.85 * night_factor;
	vec3 sky = sky_tint.rgb * window_gain * day;
	float net = pow(clamp(1.0 - abs(r - 0.75) * 3.0, 0.0, 1.0), 4.0);
	vec3 c = mix(deep_color * day, sky * (0.85 + 0.35 * net), window);
	float fog = 1.0 - exp(-length(VERTEX) * fog_per_m);
	c = mix(c, fog_color * day, fog * (1.0 - 0.5 * window));
	ALBEDO = cs_out(c);
}
