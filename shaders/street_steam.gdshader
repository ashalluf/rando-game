shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert, specular_disabled;

// Steam rising out of a manhole or a kerb inlet (scripts/world/street_clutter_2.gd, K_STEAM).
// Four puffs per plume, each a quad turned to the camera about the vertical axis, spread and
// drifted downwind as it rises; the billows scroll up out of value noise and fade with height.
// INSTANCE_CUSTOM: r phase, g strength, b 1 for an inlet (a flatter, wider wisp out of the slot).
// Lit (the sun and sky shade it) and, at night, warmed by the street lamps (lamp_factor). Works
// in linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;
global uniform float lamp_factor;
global uniform float night_factor;
global uniform float rain_intensity;
global uniform vec2 wind_lean;

uniform float opacity = 0.9;
uniform float rise = 0.55;

varying float v_alpha;
varying vec2 v_uv;
varying float v_puff;
varying float v_seed;

float h1(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1.0, 0.0)), f.x), mix(h1(i + vec2(0.0, 1.0)), h1(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float puff = UV2.x;
	float y0 = UV2.y;
	float phase = INSTANCE_CUSTOM.r;
	float inlet = INSTANCE_CUSTOM.b;
	float up = VERTEX.y;
	float k = clamp(up / 4.4, 0.0, 1.0);
	// Wider and leaning downwind as it rises; an inlet's wisp hugs the kerb at first.
	float width = mix(0.75, 2.6, k) * mix(1.0, 1.4, inlet);
	vec3 wind_dir = normalize(vec3(wind_lean.x + 0.35, 0.0, wind_lean.y + 0.2));
	float wind = 0.35 + clamp(wind_factor, 0.0, 1.5);
	vec3 drift = wind_dir * wind * k * k * 2.2 + vec3(sin(TIME * 0.7 + phase * 20.0 + up), 0.0, cos(TIME * 0.53 + phase * 13.0)) * 0.15 * k;
	// Turn the quad to the camera about the vertical, in model space.
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 to_cam = cam - vec3(0.0, up, 0.0);
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), length(to_cam) > 0.01 ? to_cam : vec3(0.0, 0.0, 1.0)));
	VERTEX = right * VERTEX.x * width + vec3(0.0, up * mix(1.0, 0.6, inlet), 0.0) + drift;
	NORMAL = normalize(to_cam + vec3(0.0, 0.5, 0.0));
	v_uv = UV;
	v_puff = puff;
	v_seed = phase;
	// More steam on a cold night or in the rain.
	float strength = INSTANCE_CUSTOM.g * (0.6 + 0.4 * night_factor + 0.3 * rain_intensity);
	v_alpha = strength * (1.0 - smoothstep(0.55, 1.0, k)) * smoothstep(0.0, 0.08, up);
}

void fragment() {
	// Billows scrolling up; the quad's sides feathered.
	vec2 p = vec2(v_uv.x * 1.6, v_uv.y * 1.2 + v_puff * 0.9);
	float t = TIME * rise;
	float n = n2(p * 3.0 - vec2(0.0, t * 2.0) + v_seed * 31.0) * 0.6 + n2(p * 7.0 - vec2(t * 0.3, t * 3.4) + v_seed * 7.0) * 0.4;
	float side = 1.0 - smoothstep(0.15, 0.5, abs(v_uv.x - 0.5));
	float cap = smoothstep(0.0, 0.25, v_uv.y) * (1.0 - smoothstep(0.7, 1.0, v_uv.y));
	float a = clamp((n - 0.22) * 2.4, 0.0, 1.0) * side * cap * v_alpha * opacity;
	if (a < 0.004) {
		discard;
	}
	vec3 col = vec3(0.82, 0.83, 0.85);
	ALBEDO = cs_out(col);
	// Scattered light: steam is bright wherever it is lit, so it never reads as a dark smear.
	EMISSION = cs_out(col * 0.18 + vec3(1.0, 0.65, 0.35) * lamp_factor * 0.12);
	ALPHA = a;
}
