shader_type spatial;
// Moving cloud shadows on everything the camera sees (CloudShadows, scripts/world/cloud_shadows.gd):
// one full-screen quad that MULTIPLIES the lit picture, after the opaque pass and before the
// transparents, by how much sun the clouds overhead let through at each pixel's ground point
// (cloud_shadow.gdshaderinc: the sky volume's own columns, so a shadow lies under the cloud you
// see, offset by the sun and drifting with it). Forward+ desktop only, only while the volume is
// drawn: the picture here is linear HDR, so the multiply happens before AgX.
//
// The sun's share of a pixel's light is not known here, so it is estimated: a face turned from
// the sun (the normal buffer) loses little, glass and water (low roughness: mostly mirror) lose
// less, and the far haze, which is the sky's light, loses less with distance.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mul, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/cloud_shadow.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
global uniform vec3 origin_shift;
global uniform vec3 sun_direction;

// How much of a pixel's light goes with the sun under a full shadow (the sky's fill stays).
uniform float strength = 0.0;
// A face turned away from the sun keeps this share of the darkening (it is lit by the sky, and a
// cloud takes a little of that too).
uniform float shade_keep = 0.25;
// Mirror-like surfaces (roughness under ~0.15) keep this share.
uniform float mirror_keep = 0.45;
// Distances (m) over which the darkening fades into the haze, and how much is left past them.
uniform float fade_near = 1500.0;
uniform float fade_far = 9000.0;
uniform float far_keep = 0.35;
// 1 paints the raw shadow field (white = full sun) for tuning (CLOUD_SHADOW_DEBUG=1).
uniform float debug_field = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float depth = textureLod(depth_tex, uv, 0.0).r;
	// Reverse Z: 0 is the sky, which a cloud shadow never touches.
	if (depth < 0.0000001 || strength <= 0.001) {
		discard;
	}
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float dist = length(view.xyz);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz + origin_shift;
	vec3 L = normalize(sun_direction);
	float sh = cs_shadow(world, L);
	if (debug_field > 0.5) {
		ALBEDO = vec3(1.0 - sh) * 4.0;
	} else {
		if (sh <= 0.002) {
			discard;
		}
		vec4 nr = textureLod(nr_tex, uv, 0.0);
		float rough = nr.w > 0.5 ? 1.0 - nr.w : nr.w;
		rough /= (127.0 / 255.0);
		vec3 n = normalize(mat3(INV_VIEW_MATRIX) * (nr.xyz * 2.0 - 1.0));
		float lit = mix(shade_keep, 1.0, smoothstep(-0.02, 0.25, dot(n, L)));
		lit *= mix(mirror_keep, 1.0, smoothstep(0.08, 0.3, rough));
		lit *= mix(1.0, far_keep, smoothstep(fade_near, fade_far, dist));
		ALBEDO = vec3(1.0 - strength * sh * lit);
	}
}
