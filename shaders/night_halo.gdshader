shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

// The halo of light round a street lamp's head or a lit shop front in the night air
// (NightAtmos, scripts/world/night_atmos.gd): one quad per light in the chunk's batch, turned to
// the camera here, sized by the air (night_atmos.x) and never smaller than a couple of pixels, so
// a street of lamps reads as a row of glowing points from a block away and as soft globes in the
// rain up close. A lamp looked at nearly straight on, close by, throws a thin horizontal lens
// streak. Nothing per lamp on the CPU: the instance carries the light's base radius in its scale,
// its colour (raw, as NightCity.lamp_light() gives it) and in INSTANCE_CUSTOM r its strength,
// g the kind (0 a lamp head: a hot core; 1 a shop front: a broad glow, no core).
// Additive, fog-free (the fog would ADD its colour to an additive quad): the air's loss is
// nh_far(). By day lamp_factor is 0 and the quad collapses in the vertex stage, so it costs no
// pixels at all.

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/night_halo.gdshaderinc"

global uniform float lamp_factor;

// The hot core's radius (x the light's base radius) and its least size in pixels.
uniform float core_size = 0.16;
uniform float core_min_px = 1.7;
uniform float core_gain = 2.2;
uniform float halo_gain = 0.6;
uniform float streak_gain = 0.55;
// The streak's half length in halo radii.
uniform float streak_len = 6.0;
// No halo within this of the eye (standing under the lamp you see its light, not a ball of it).
uniform float near_fade = 3.5;
// How far a halo is pulled toward the eye so the head's own mesh never cuts it.
uniform float pull = 0.55;
// Shop fronts: a broad, dim glow off the glass.
uniform float shop_gain = 0.32;

varying vec2 v_q;
varying float v_ex;
varying float v_core_r;
varying float v_core;
varying float v_halo;
varying float v_streak;
varying vec3 v_col;

void vertex() {
	float lamp = lamp_factor * night_atmos.z * INSTANCE_CUSTOM.r;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(c);
	if (lamp < 0.002 || dist < 0.5) {
		VERTEX = vec3(0.0);
	} else {
		float shop = step(0.5, INSTANCE_CUSTOM.g);
		float s = length(MODEL_MATRIX[0].xyz);
		float R = nh_radius(s);
		float px = nh_metre_px(dist, PROJECTION_MATRIX);
		// A core under a couple of pixels is drawn at that size with its light spread over it.
		float core_w = core_size * s;
		float spread = 1.0;
		if (core_w < core_min_px * px) {
			spread = clamp(core_w / (core_min_px * px), 0.35, 1.0);
			spread *= spread;
			core_w = core_min_px * px;
		}
		R = max(R, core_w * 2.6);
		float fade = smoothstep(near_fade, near_fade * 2.2, dist) * nh_far(dist);
		float st = shop > 0.5 ? 0.0 : nh_streak(c, dist) * streak_gain * min(lamp, 1.0);
		float ex = st > 0.002 ? streak_len : 1.0;
		c -= normalize(c) * min(pull * s, dist * 0.25);
		VERTEX = c + vec3(VERTEX.x * ex * R, VERTEX.y * R, 0.0);
		v_q = vec2((VERTEX.x - c.x) / R, (VERTEX.y - c.y) / R);
		v_ex = ex;
		v_core_r = core_w / R;
		v_core = (1.0 - shop) * core_gain * spread * lamp * mix(1.0, fade, 0.5) * smoothstep(near_fade * 0.5, near_fade, dist);
		v_halo = (shop > 0.5 ? shop_gain : halo_gain) * nh_halo_amount() * lamp * fade;
		v_streak = st * fade;
		v_col = cs_srgb_to_linear(COLOR.rgb);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float a = nh_shape(v_q, v_ex, v_core_r, v_core, v_halo, v_streak);
	ALBEDO = cs_out(v_col * a);
}
