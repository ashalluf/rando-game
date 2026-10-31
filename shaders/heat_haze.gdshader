shader_type spatial;
// Heat shimmer on a hot afternoon (HeatHaze, scripts/world/heat_haze.gd): one
// full-screen quad that reads the opaque picture and redraws it nudged by rising, wobbling
// refraction where light has crossed a long stretch of hot air close to the ground - the far end
// of a street, the far field, the horizon. The nudge is strongest along grazing rays (looking
// along the ground, not down at it) and grows with distance from `near` to `far`; nothing near the
// camera moves. It reads the screen, so it draws FIRST among the transparents (render_priority
// MIN, as the explosion shimmer does) and everything transparent lands on top of it.
// Forward+ only (HeatHaze never builds it elsewhere); the screen texture is linear HDR there and
// is written back as it was read.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float strength = 0.0;
// Distances (m) the shimmer grows over, and how far up from the horizon (sine of the ray's
// elevation) it reaches.
uniform float near = 30.0;
uniform float far = 450.0;
uniform float graze = 0.07;
// Peak displacement in 1080-line pixels.
uniform float max_px = 2.4;

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
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float depth = textureLod(depth_tex, uv, 0.0).r;
	// The sky has no depth (reverse Z: 0 is infinitely far): treat it as far, and take the ray's
	// direction from a point in front of the camera, never from the depth.
	float dist = far;
	if (depth > 0.000001) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth, 1.0);
		dist = length(view.xyz / view.w);
	}
	vec4 fwd = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, 0.5, 1.0);
	vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * (fwd.xyz / fwd.w));
	float amt = smoothstep(near, far, dist) * (1.0 - smoothstep(graze * 0.3, graze, abs(ray.y)));
	amt *= strength;
	if (amt <= 0.002) {
		discard;
	}
	vec2 disp;
	{
		// Rising cells of hot air: the pattern climbs and wobbles, finer far off.
		vec2 p = vec2(uv.x * 160.0, uv.y * 90.0 + TIME * 3.2);
		float a = vnoise(p) - 0.5;
		float b = vnoise(p * 2.3 + vec2(TIME * 0.7, -TIME * 1.9)) - 0.5;
		disp = vec2(a * 0.35, a + b * 0.6) * amt * max_px / VIEWPORT_SIZE.y;
		disp.x *= VIEWPORT_SIZE.y / max(VIEWPORT_SIZE.x, 1.0);
	}
	vec3 c = textureLod(screen_tex, uv + disp, 0.0).rgb;
	ALBEDO = c;
	ALPHA = 1.0;
}
