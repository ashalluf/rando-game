shader_type spatial;
render_mode cull_disabled;

// A golf flag (GolfBuild.flag_mesh(): a cloth grid off the stick along +X, UV.x 0 at the stick, 1 at
// the fly end, its top at y 0). It waves in the wind the weather publishes (`wind_factor`): a
// travelling wave whose height grows toward the fly end, a droop when the air is still, the
// whole flag swinging a little about the stick. INSTANCE_CUSTOM.r is the flag's phase (a hash),
// the instance colour its nylon. Linear on both renderers (color_space.gdshaderinc).

global uniform float wind_factor;
global uniform float night_factor;

uniform float wave_amp = 0.065;
uniform float wave_len = 0.34;
uniform float wave_speed = 7.5;

varying vec3 nylon;

#include "res://shaders/color_space.gdshaderinc"

void vertex() {
	float u = UV.x;
	float v = UV.y;
	float wind = clamp(0.35 + wind_factor, 0.15, 2.0);
	float ph = INSTANCE_CUSTOM.r * 6.2831853;
	float t = TIME * wave_speed * (0.7 + 0.3 * wind) + ph;
	// The cloth's ripple: a wave travelling to the fly end, a second shorter one across it.
	float w = sin(u * 6.2831853 / wave_len - t) + 0.35 * sin(u * 17.0 - t * 1.7 + v * 3.0);
	VERTEX.z += w * wave_amp * u * min(wind, 1.2);
	// Still air: the fly end hangs; a gust lifts it straight out.
	float droop = (1.0 - smoothstep(0.2, 1.0, wind)) * u * u * 0.22;
	VERTEX.y -= droop;
	VERTEX.x -= droop * 0.4;
	// A swing about the stick.
	float swing = sin(TIME * 1.3 + ph) * 0.18 * wind * u;
	VERTEX.z += swing * 0.51;
	// The normal off the ripple's slope.
	float dz = cos(u * 6.2831853 / wave_len - t) * 6.2831853 / wave_len * wave_amp * u * min(wind, 1.2);
	NORMAL = normalize(NORMAL + vec3(-dz, 0.0, 0.0) * sign(NORMAL.z));
	nylon = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	vec3 c = nylon;
	// Seam hem along the stick side and a faint sheen.
	c *= mix(0.82, 1.0, smoothstep(0.02, 0.06, UV.x));
	ALBEDO = cs_out(c * (1.0 - 0.4 * clamp(night_factor, 0.0, 1.0)));
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	BACKLIGHT = cs_out(c * 0.45);
}
