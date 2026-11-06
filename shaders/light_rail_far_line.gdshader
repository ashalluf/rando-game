shader_type spatial;
render_mode cull_back;

// The Coral Line past the streamed chunks (LightRailSystem._build_far_line()): the structure, its
// columns, the trackway and the stations' canopies as plain vertex-coloured faces (sRGB in the
// rgb; alpha 1 = a lit canopy soffit, which glows after dark), dithered in from `fade_start`
// metres from the camera; inside the FULL chunks' own works wherever both draw.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform float fade_start = 150.0;
uniform float fade_width = 60.0;

varying vec3 wp;


void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float keep = clamp((dist - fade_start) / fade_width, 0.0, 1.0);
	// Ordered dither: a 4x4 Bayer threshold per pixel.
	ivec2 q = ivec2(FRAGCOORD.xy) % 4;
	int idx = q.x + q.y * 4;
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (keep <= (bayer[idx] + 0.5) / 16.0) {
		discard;
	}
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	ALBEDO = cs_out(base);
	ROUGHNESS = 0.85;
	EMISSION = cs_out(vec3(1.0, 0.92, 0.78) * 1.6 * COLOR.a * clamp(lamp_factor, 0.0, 1.0));
}
