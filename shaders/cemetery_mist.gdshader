shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
// The memorial park's dawn ground mist (Rc5CemeteryDawn.mist_box()): drawn on the back faces of a
// box over a chunk's part of the site (so from inside it or outside it); each fragment follows the
// view ray's chord through the box, cut short by the scene's depth, and integrates a mist that
// thins with height over the park's rise (Cemetery.height()'s dome, mirrored loosely: crown,
// height, four extents), wisped by a slow drifting noise. Everything is in the box's own space
// (its centre the origin), so no origin shift is needed. `amount` 0 discards (all but the
// morning). Linear on both renderers (color_space.gdshaderinc); the colour is the fog's light.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float amount = 0.0;
uniform vec3 mist_color = vec3(0.6, 0.63, 0.67);
// The mist's density at the turf (per metre) and how fast it thins with height (m).
uniform float density = 0.022;
uniform float scale_height = 2.6;
// (crown x, crown z, rise height H, the turf's y at the rise's foot), box space.
uniform vec4 crown = vec4(0.0, 0.0, 0.0, -5.0);
// The rise's extents from the crown: -x, +x, -z, +z.
uniform vec4 extent = vec4(60.0);
uniform vec3 half_size = vec3(50.0, 8.0, 50.0);
// The wisps: scale (1/m), drift (m/s) and how deep they cut.
uniform float wisp_scale = 0.045;
uniform float wisp_drift = 0.35;
uniform float wisp_depth = 0.7;

float cm_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float cm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cm_hash(i), cm_hash(i + vec2(1.0, 0.0)), f.x), mix(cm_hash(i + vec2(0.0, 1.0)), cm_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cm_ground(vec2 q) {
	vec2 d = q - crown.xy;
	float ux = d.x / (d.x > 0.0 ? extent.y : extent.x);
	float uz = d.y / (d.y > 0.0 ? extent.w : extent.z);
	float r = pow(pow(abs(ux), 3.0) + pow(abs(uz), 3.0), 1.0 / 3.0);
	return crown.w + crown.z * (1.0 - smoothstep(0.12, 1.0, r));
}

void fragment() {
	if (amount <= 0.001) {
		discard;
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = CAMERA_POSITION_WORLD - origin;
	vec3 frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - origin;
	vec3 dir = normalize(frag - cam);
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_t = length(vp.xyz / vp.w);
	// The chord through the box (slab test).
	vec3 safe = sign(dir) * max(abs(dir), vec3(1e-5)) + vec3(step(abs(dir), vec3(0.0))) * 1e-5;
	vec3 inv = 1.0 / safe;
	vec3 ta = (-half_size - cam) * inv;
	vec3 tb = (half_size - cam) * inv;
	vec3 tmin = min(ta, tb);
	vec3 tmax = max(ta, tb);
	float t0 = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float t1 = min(min(min(tmax.x, tmax.y), tmax.z), scene_t);
	if (t1 <= t0) {
		discard;
	}
	// Ten samples along it, dithered a little per pixel so the steps never band.
	float jit = cm_hash(FRAGCOORD.xy) - 0.5;
	float acc = 0.0;
	const int N = 10;
	vec2 drift = vec2(TIME * wisp_drift, TIME * wisp_drift * 0.4);
	for (int i = 0; i < N; i++) {
		float t = mix(t0, t1, (float(i) + 0.5 + jit * 0.8) / float(N));
		vec3 p = cam + dir * t;
		float h = max(p.y - cm_ground(p.xz), 0.0);
		float w = cm_noise((p.xz + drift) * wisp_scale) * 0.65 + cm_noise((p.xz - drift * 1.7) * wisp_scale * 2.9) * 0.35;
		acc += exp(-h / scale_height) * mix(1.0, w * 1.6, wisp_depth);
	}
	float tau = acc / float(N) * (t1 - t0) * density * amount;
	ALBEDO = cs_out(mist_color);
	ALPHA = clamp(1.0 - exp(-tau), 0.0, 0.92);
}
