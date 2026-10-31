shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

// A street lamp's reflection in the wet road (NightAtmos, the night street review 2026-10-30):
// the one thing a rainy night street is made of, and nothing drew it - the Compatibility renderer
// has no screen-space reflections at all, and Forward+'s miss every lamp above the frame's top.
// One flat quad per FULL lamp in the lamp's own prop record (key "atmos_glow_wet", so a popped lamp
// takes its reflection), lying on the ground: the instance's origin is the ground under the lamp's
// head, its basis y length the head's height over it. Here, every frame, the quad is laid where a
// mirror would show the head - on the line from the lamp's foot to the camera, at h / (h + eye
// height) of the way (the mirror image's ground point) - and stretched along that line toward the
// viewer, the long smeared streak a rough wet surface makes of a point light. Gone while the road
// is dry or the lamps are off (collapsed in the vertex stage: no pixels).

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/night_halo.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// Brightest point of the streak (x the lamp's colour, the wetness and lamp_factor).
uniform float gain = 0.9;
// Forward+ adds its own screen-space reflection of a lamp that is in the frame.
uniform float gain_forward = 0.6;
// The streak's half width as a share of its distance from the eye (about the same few pixels
// across near and far, as the blur of a lamp in a rough wet road is).
uniform float width_share = 0.009;
uniform float width_min = 0.05;
// Where it starts, as a share of the way from the lamp's foot to the mirror point (the pole's
// foot is mirrored at the foot itself, dark), and how far it smears on past the mirror point toward
// the eye: a share of what is left of the way, at most smear_max metres.
uniform float start_share = 0.1;
uniform float smear_share = 0.45;
uniform float smear_max = 7.0;
// The road wetness at which the reflection is fully there.
uniform float wet_full = 0.55;
// The water broken up: ripples and rain move bright and dark patches along the streak.
uniform float ripple = 0.55;

varying float v_amp;
varying float v_peak;
varying vec3 v_col;
varying vec2 v_world;

float nw_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float nw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(nw_hash(i), nw_hash(i + vec2(1.0, 0.0)), f.x), mix(nw_hash(i + vec2(0.0, 1.0)), nw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float wet = smoothstep(0.04, wet_full, road_wetness);
	vec3 foot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec2 to_cam = cam.xz - foot.xz;
	float d = length(to_cam);
	float eye = cam.y - foot.y;
	if (lamp_factor < 0.01 || wet < 0.002 || d < 1.0 || eye < 0.3 || night_atmos.z < 0.002) {
		VERTEX = vec3(0.0);
	} else {
		vec2 u = to_cam / d;
		vec2 v = vec2(-u.y, u.x);
		// The mirror point: where the ray from the eye to the head's mirror image meets the road.
		float rd = d * h / (h + eye);
		float s0 = rd * start_share;
		float s1 = rd + min((d - rd) * smear_share, smear_max);
		float s = VERTEX.y > 0.0 ? s1 : s0;
		vec2 p0 = foot.xz + u * s;
		float w = max(width_min, width_share * length(vec3(p0.x, foot.y, p0.y) - cam));
		vec2 p = p0 + v * (VERTEX.x * w);
		vec3 world = vec3(p.x, foot.y + 0.035, p.y);
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		v_world = world.xz;
		v_peak = (rd - s0) / max(s1 - s0, 1e-3);
		float dist = length(VERTEX);
		float g = gain;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		g = gain_forward;
#endif
		v_amp = g * wet * min(lamp_factor, 1.0) * night_atmos.z * INSTANCE_CUSTOM.r * nh_far(dist);
		v_col = cs_srgb_to_linear(COLOR.rgb);
	}
}

void fragment() {
	// UV: x 0..1 across; y 1 at the lamp's end, 0 at the eye's (the mesh's own UVs).
	float across = abs(UV.x * 2.0 - 1.0);
	float t = 1.0 - UV.y;
	float pk = clamp(v_peak, 0.05, 0.95);
	// Rising from the foot to the mirror point, then dying away toward the eye.
	float along = t < pk ? pow(t / pk, 1.4) : pow(max(1.0 - (t - pk) / (1.0 - pk), 0.0), 2.0);
	// Ripples: two drifting value-noise bands across the streak's length in true world metres.
	float n1 = nw_noise(v_world * 2.3);
	float n2 = nw_noise(v_world * 0.85 + vec2(TIME * 0.6, 0.0));
	float broken = mix(1.0, 0.35 + 1.1 * n1 * n2 + 0.2 * n2, ripple);
	float a = exp(-across * across * 6.0) * along * broken;
	ALBEDO = cs_out(v_col * a * v_amp);
}
