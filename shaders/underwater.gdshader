shader_type canvas_item;

// Under the water (Swim, scripts/player/swim.gd): one full-screen pass over the 3D picture, on
// its own CanvasLayer under the vignette's, shown only while the camera is under the surface.
// Water takes the red out of the light first, then the green, so everything goes blue-green and
// darker with depth; light scatters, so the picture is softer and veiled toward the water's own
// colour; and the picture wobbles as if through moving water. The picture is the tonemapped one
// (display values), so the colours here are display values too, on both renderers.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Metres from the surface down to the camera.
uniform float depth_m = 1.0;
// The water's own colour near the surface by day (display values), and the night's dimming.
uniform vec3 water_color = vec3(0.05, 0.32, 0.36);
uniform float light = 1.0;
// The veil at the surface and how much more each metre adds.
uniform float veil = 0.32;
uniform float veil_per_m = 0.025;
// Red, green, blue taken out per metre of depth (plus a two-metre path to the eye).
uniform vec3 absorb = vec3(0.30, 0.07, 0.05);
uniform float wobble = 0.0035;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	uv += wobble * vec2(sin(uv.y * 23.0 + t * 1.7) + 0.5 * sin(uv.y * 51.0 - t * 2.3),
		cos(uv.x * 19.0 + t * 1.3) + 0.5 * cos(uv.x * 47.0 + t * 2.9));
	// Scattering: a soft picture, softer the deeper.
	float lod = 1.2 + clamp(depth_m * 0.08, 0.0, 1.3);
	vec3 c = textureLod(screen_tex, uv, lod).rgb;
	c *= exp(-absorb * (2.0 + depth_m));
	float dim = exp(-depth_m * 0.06) * light;
	float v = clamp(veil + depth_m * veil_per_m, 0.0, 0.85);
	c = mix(c, water_color * dim, v);
	// Light from above: brighter toward the top of the frame.
	c *= mix(0.75, 1.12, smoothstep(0.0, 1.0, 1.0 - SCREEN_UV.y));
	vec2 d = SCREEN_UV - vec2(0.5);
	c *= 1.0 - 0.45 * smoothstep(0.25, 0.75, length(d));
	COLOR = vec4(c, 1.0);
}
