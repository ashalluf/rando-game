shader_type spatial;
render_mode cull_disabled;
// A flag on a civic building's pole (CivicKit.flag_mesh(): UV 0..1, hoist at u 0, flying toward
// +x). The vertex shader waves it - travelling waves growing from the hoist, a droop by the fly -
// and the fragment paints it: kind 0 the national stars and stripes (13 stripes, a blue canton
// with rows of stars), kind 1 the city's own invented flag (a gold sun over blue and white waves).
// The cloth's shading comes from the waved normal; a little light through it from behind.
#include "res://shaders/color_space.gdshaderinc"

global uniform float wind_factor;

uniform int kind = 0;
uniform float flag_len = 1.83;

varying float wave_shade;

void vertex() {
	float u = UV.x;
	float wind = 0.6 + 0.8 * clamp(wind_factor, 0.0, 1.5);
	float amp = 0.12 * u * wind;
	float ph = TIME * (3.2 + wind) - u * 9.0 + (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.37;
	float w = sin(ph) + 0.35 * sin(ph * 2.1 + 1.3);
	VERTEX.z += amp * w;
	VERTEX.y -= u * u * 0.12 * (1.6 - wind);
	float dz = amp * (cos(ph) + 0.7 * cos(ph * 2.1 + 1.3)) * -9.0 / flag_len;
	NORMAL = normalize(vec3(-dz, 0.0, 1.0));
	wave_shade = 0.8 + 0.2 * cos(ph);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 c;
	if (kind == 0) {
		float stripe = floor(uv.y * 13.0);
		c = mod(stripe, 2.0) < 0.5 ? vec3(0.62, 0.05, 0.10) : vec3(0.95, 0.94, 0.92);
		if (uv.x < 0.4 && uv.y < 7.0 / 13.0) {
			c = vec3(0.07, 0.12, 0.36);
			vec2 g = vec2(uv.x / 0.4 * 12.0, uv.y / (7.0 / 13.0) * 10.0);
			vec2 cell = floor(g);
			vec2 f = fract(g) - 0.5;
			float offset_row = mod(cell.y, 2.0);
			float star = (mod(cell.x + offset_row, 2.0) < 0.5 && cell.x > 0.0 && cell.x < 11.0 && cell.y > 0.0 && cell.y < 9.0) ? 1.0 - smoothstep(0.18, 0.3, length(f)) : 0.0;
			c = mix(c, vec3(0.95), star);
		}
	} else {
		// The city's flag: blue over a white wave and a blue sea, a gold sun rising.
		float wave = 0.36 + 0.04 * sin(uv.x * 18.0);
		c = uv.y < wave ? vec3(0.08, 0.22, 0.52) : vec3(0.08, 0.30, 0.62);
		c = mix(c, vec3(0.95, 0.94, 0.9), step(wave, uv.y) * step(uv.y, wave + 0.08));
		float sun = 1.0 - smoothstep(0.16, 0.17, length((uv - vec2(0.5, 0.62)) * vec2(1.9, 1.0)));
		c = mix(c, vec3(0.92, 0.66, 0.16), sun * step(wave + 0.08, uv.y));
	}
	c *= wave_shade;
	ALBEDO = cs_out(c * c);
	ROUGHNESS = 0.85;
	BACKLIGHT = cs_out(c * c * 0.35);
}
