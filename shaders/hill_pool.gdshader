shader_type spatial;
render_mode cull_back;

// The pools of the hillside houses (HillHomeKit): a water sheet to the rim over a tiled tank the
// shader makes up - turquoise deepening with the depth it reads as (COLOR.g, 0..1 over 2.5 m), the
// tank's tile joints and a caustic net wobbling under the ripples, the sky mirrored by fresnel and
// EMITTED (a reflection does not depend on the light falling on it), and after dark the pool's
// own underwater lights (lamp_factor), which is what a Hollywood Hills pool is at night: a block
// of glowing turquoise on a terrace over the city. COLOR.r 1 is the sheet spilling over an
// infinity edge (falling streaks, white where it breaks). UV in metres.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform float lamp_factor;
global uniform vec4 sky_tint;

uniform vec3 shallow = vec3(0.10, 0.52, 0.56);
uniform vec3 deep = vec3(0.012, 0.16, 0.26);
uniform vec3 night_glow = vec3(0.04, 0.55, 0.62);
uniform float night_energy = 0.9;
uniform float ripple = 0.035;

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec2 q = UV;
	float t = TIME;
	float spill = step(0.5, COLOR.r);
	// Ripples: a few crossing waves, their slope as the normal.
	vec2 g = vec2(0.0);
	g += vec2(0.8, 0.3) * cos(dot(q, vec2(2.1, 0.7)) * 3.0 + t * 1.3);
	g += vec2(-0.4, 0.9) * cos(dot(q, vec2(-0.9, 1.9)) * 3.4 + t * 1.1);
	g += vec2(0.5, -0.6) * cos(dot(q, vec2(1.3, -1.6)) * 5.1 + t * 1.9) * 0.5;
	vec3 n = normalize(vec3(-g.x * ripple, 1.0, -g.y * ripple));
	if (spill > 0.5) {
		n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	float ndv = clamp(dot(n, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	float day = 1.0 - clamp(night_factor, 0.0, 1.0);
	float d = clamp(COLOR.g, 0.0, 1.0);
	// The tank under it, offset by the refraction: tile joints and the caustic net.
	vec2 tq = q + g * 0.08 + V.xz * d * 0.6;
	vec2 tile = abs(fract(tq / 0.3) - 0.5);
	float joint = smoothstep(0.47, 0.5, max(tile.x, tile.y));
	float c1 = abs(sin(tq.x * 4.3 + sin(tq.y * 3.1 + t * 0.9) * 1.4 + t * 0.6));
	float c2 = abs(sin(tq.y * 4.7 + sin(tq.x * 2.7 - t * 0.8) * 1.4 - t * 0.5));
	float caustic = pow(1.0 - min(c1, c2), 6.0);
	float far = smoothstep(30.0, 90.0, length(CAMERA_POSITION_WORLD - wpos));
	vec3 body = mix(shallow, deep, d) * (1.0 - 0.25 * joint * (1.0 - far));
	vec3 lit_body = body * (sky * 0.9 + vec3(0.25)) * day + shallow * caustic * 0.6 * day * (1.0 - far);
	// After dark: the underwater lights.
	float lamp = clamp(max(lamp_factor, night_factor), 0.0, 1.0);
	vec3 glow = night_glow * night_energy * lamp * (0.75 + 0.25 * caustic) * mix(1.0, 0.65, d);
	vec3 water = (lit_body + glow) * (1.0 - fres);
	vec3 mirror = sky * fres * (1.0 - 0.7 * night_factor);
	if (spill > 0.5) {
		// The falling sheet: streaks running down it.
		float streak = 0.6 + 0.4 * h21(vec2(floor(q.x * 22.0), floor(q.y * 3.0 - t * 6.0)));
		water = mix(body * 1.4, vec3(0.75, 0.85, 0.86), 0.35 * streak) * (sky * 0.7 * day + glow * 0.8 + vec3(0.05));
		mirror *= 0.5;
	}
	ALBEDO = cs_out(vec3(0.02));
	ROUGHNESS = 0.03;
	SPECULAR = 0.5;
	NORMAL = spill > 0.5 ? NORMAL : normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	EMISSION = cs_out(water + mirror);
}
