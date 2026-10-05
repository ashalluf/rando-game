shader_type spatial;
// The brush fire's smoke column (SantaAnaFx): camera-facing puffs a hundred metres and more
// across, rising off a ridge and laid over by the Santa Ana. Shaded here, not by the renderer:
// a billboard lit by the sun is one flat tone, so each puff is lit as a ball (its sunward side
// bright, a darker core) from the colours the script hands over, and after dark its underside
// glows with the fire under it. Colours are LINEAR (plain uniforms, Vector3 from script) and go
// out through cs_out() (color_space.gdshaderinc).
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 smoke_col = vec3(0.30, 0.26, 0.22);
uniform vec3 light_col = vec3(1.0, 0.92, 0.80);
uniform vec3 amb_col = vec3(0.25, 0.28, 0.33);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
// The fire's glow on the column after dark: colour (linear, energy included) and the ground
// height it falls off from, over `glow_fall` metres.
uniform vec3 glow_col = vec3(0.0);
uniform float fire_y = 0.0;
uniform float glow_fall = 380.0;
uniform float opacity = 0.0;

varying vec3 wpos;
varying vec3 axis_x;
varying vec3 axis_y;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// Billboard keeping the particle's scale, turned by its angle (CPUParticles3D puts the angle
	// in INSTANCE_CUSTOM.x).
	float s = length(MODEL_MATRIX[0].xyz);
	float ang = INSTANCE_CUSTOM.x;
	vec2 v = vec2(cos(ang) * VERTEX.x - sin(ang) * VERTEX.y, sin(ang) * VERTEX.x + cos(ang) * VERTEX.y) * s;
	axis_x = INV_VIEW_MATRIX[0].xyz;
	axis_y = INV_VIEW_MATRIX[1].xyz;
	vec3 w = MODEL_MATRIX[3].xyz + axis_x * v.x + axis_y * v.y;
	wpos = w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	// A billow: the disc's edge pushed in and out by noise, so a puff is never a round ball.
	float seed = COLOR.r * 31.7;
	float n = vnoise(q * 2.6 + seed) * 0.6 + vnoise(q * 6.1 - seed) * 0.4;
	float edge = 1.0 - smoothstep(0.45 + n * 0.35, 0.95, r);
	float a = edge * COLOR.a * opacity;
	// Lit as a ball: a normal out of the disc toward the camera.
	vec3 nrm = normalize(axis_x * q.x + axis_y * -q.y + normalize(CAMERA_POSITION_WORLD - wpos) * sqrt(max(1.0 - r * r, 0.05)));
	float lit = clamp(dot(nrm, sun_dir) * 0.55 + 0.45, 0.0, 1.0) * smoothstep(-0.12, 0.08, sun_dir.y);
	vec3 col = smoke_col * (amb_col + light_col * lit) * (0.85 + 0.3 * n);
	// The fire under it, after dark: an orange underside fading up the column.
	float low = exp(-max(wpos.y - fire_y, 0.0) / glow_fall);
	col += glow_col * low * (0.6 + 0.4 * (1.0 - q.y * 0.5)) * (0.7 + 0.3 * n);
	ALBEDO = cs_out(col);
	ALPHA = clamp(a, 0.0, 1.0);
}
