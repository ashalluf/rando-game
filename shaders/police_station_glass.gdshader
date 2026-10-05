shader_type spatial;
render_mode cull_back;
// A police station's glazing (PoliceStation): tinted glass that mirrors the sky by Fresnel by day
// and, after dark, shows the offices behind it lit window by window - ceiling panels, a warm or a
// cool tube colour, blinds part drawn - and the public lobby lit all night. UV is metres (x along
// the wall, y up), which is what PoliceStation.Geo writes. Works in linear on both renderers
// (color_space.gdshaderinc).
#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform vec4 sky_tint;

// One window bay (m along) by one storey (m up).
uniform vec2 cell = vec2(1.6, 3.8);
// Share of the offices still lit at night.
uniform float lit_share = 0.62;
// 1: the public lobby (lit all night, brighter, warm; a little light by day too).
uniform float lobby = 0.0;
uniform float seed = 0.0;
// Glass body colour (linear) and how much of the sky it mirrors.
uniform vec3 tint = vec3(0.020, 0.032, 0.040);
uniform float mirror = 0.55;
uniform float night_energy = 1.6;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 q = uv / cell;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float r = h21(id);
	// Mullions at the bay lines and the transom low in the storey.
	float px = fwidth(q.x) + 1e-4;
	float mull = 1.0 - smoothstep(0.015, 0.015 + px * 1.5, min(f.x, 1.0 - f.x));
	float sky_l = dot(pow(max(sky_tint.rgb, vec3(0.0)), vec3(2.2)), vec3(0.3333));
	vec3 sky = pow(max(sky_tint.rgb, vec3(0.0)), vec3(2.2));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 albedo = mix(tint, vec3(0.055, 0.058, 0.062), mull);
	// The room: a ceiling panel band at the top of the storey, falling off down the glass, a
	// blind drawn to its own height, a dark desk line low down.
	float lit = lobby > 0.5 ? 1.0 : step(r, lit_share);
	vec3 tube = mix(vec3(1.0, 0.83, 0.62), vec3(0.82, 0.90, 1.0), step(0.55, fract(r * 7.13)));
	if (lobby > 0.5) {
		tube = vec3(1.0, 0.86, 0.68);
	}
	float ceiling = smoothstep(0.62, 0.96, f.y) * (0.6 + 0.4 * step(0.5, fract(q.x * 2.0)));
	float body = 0.32 + 0.68 * ceiling;
	float blind = 1.0 - fract(r * 3.71) * 0.55;
	float under_blind = 1.0 - 0.75 * step(blind, f.y) * step(0.4, fract(r * 5.3));
	float desk = 1.0 - 0.5 * (smoothstep(0.18, 0.2, f.y) - smoothstep(0.26, 0.28, f.y)) * step(0.3, fract(r * 9.1));
	vec3 room = tube * body * under_blind * desk * (0.55 + 0.45 * fract(r * 13.7)) * (1.0 - mull);
	float night = lamp_factor * night_energy * (lobby > 0.5 ? 2.2 : 1.0);
	float day = lobby > 0.5 ? 0.12 : 0.0;
	vec3 emit = room * lit * (night + day * (1.0 - lamp_factor));
	emit += sky * (0.08 + 0.92 * fres) * mirror * (1.0 - 0.7 * lamp_factor) * (1.0 - mull);
	ALBEDO = cs_out(albedo);
	METALLIC = 0.2;
	ROUGHNESS = mix(0.05, 0.4, mull);
	SPECULAR = 0.6;
	EMISSION = cs_out(emit);
}
