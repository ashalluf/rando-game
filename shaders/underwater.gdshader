shader_type spatial;
// Under the water (Swim, scripts/player/swim.gd): one full-screen quad (the heat haze's trick:
// the vertex stage puts it over the whole screen), shown only while the camera is under the
// surface. It reads the opaque picture and its depth and puts water between the camera and every
// pixel: light along the way is absorbed red first, then green (Beer-Lambert per channel over the
// pixel's distance plus the camera's depth, for the light that came down to it), and scattered
// toward the water's own colour, darker with depth and at night; the picture wobbles as if seen
// through moving water. It reads the screen, so it draws FIRST among the transparents
// (render_priority MIN) and the bubbles land on top of it. Linear on both renderers
// (color_space.gdshaderinc): the Compatibility renderer's picture is in display numbers.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// Metres from the surface down to the camera.
uniform float depth_m = 1.0;
// The scattered light of the water near the surface by day (linear), and the day's share (1 day,
// 0.15 night).
uniform vec3 water_color = vec3(0.010, 0.085, 0.085);
uniform float light = 1.0;
// Metres of water that take a pixel half way into the water's colour.
uniform float visibility = 9.0;
// Red, green, blue taken out per metre of water.
uniform vec3 absorb = vec3(0.30, 0.055, 0.045);
// The sky (no depth) is this far.
uniform float far = 60.0;
uniform float wobble = 0.0035;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	uv += wobble * vec2(sin(uv.y * 23.0 + t * 1.7) + 0.5 * sin(uv.y * 51.0 - t * 2.3),
		cos(uv.x * 19.0 + t * 1.3) + 0.5 * cos(uv.x * 47.0 + t * 2.9));
	uv = clamp(uv, vec2(0.002), vec2(0.998));
	float raw = textureLod(depth_tex, uv, 0.0).r;
	float dist = far;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float ndc_z = raw * 2.0 - 1.0;
	bool sky = raw >= 0.999999;
#else
	float ndc_z = raw;
	bool sky = raw <= 0.000001;
#endif
	if (!sky) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, ndc_z, 1.0);
		dist = min(length(view.xyz / view.w), far);
	}
	vec4 fwd = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, 0.5, 1.0);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * (fwd.xyz / fwd.w));
	// Softer the further: the picture taken from a blurrier mip as the water thickens.
	float lod = clamp(dist / visibility, 0.0, 2.5);
	vec3 c = cs_in(textureLod(screen_tex, uv, lod).rgb);
	c *= exp(-absorb * (dist + depth_m * 0.5));
	// The water's own colour: brightest looking up toward the light, dark looking down, and dimmer
	// the deeper the camera is.
	vec3 water = water_color * light * exp(-depth_m * 0.07) * mix(0.35, 1.6, smoothstep(-0.6, 0.8, ray.y));
	float fog = 1.0 - exp(-dist / visibility * 0.6931);
	c = mix(c, water, fog);
	vec2 d = SCREEN_UV - vec2(0.5);
	c *= 1.0 - 0.4 * smoothstep(0.3, 0.8, length(d));
	ALBEDO = cs_out(c);
}
