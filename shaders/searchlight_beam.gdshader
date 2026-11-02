shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The visible shaft of a police searchlight where there is no volumetric fog to draw it (the web
// build, and every Quality level below HIGH): an open cone, additive, bright at the lamp and
// dying away down its length, soft at its silhouette edges. On Forward+ HIGH the SpotLight3D's
// own volumetric fog energy draws the shaft instead and Helicopter hides this.
// The cone is Godot's CylinderMesh, which runs UV.y from its top (the lamp) to its bottom.

global uniform float lamp_factor;
uniform vec3 tint : source_color = vec3(0.86, 0.92, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.22;
// Share of the shaft length over which it fades out.
uniform float length_fade : hint_range(0.05, 1.0) = 0.85;
// PoliceNightLook (1, Helicopter sets it): the shaft as a column of lit haze - a hot core down
// its axis, motes drifting through it, thicker in rain (the drops catch the light). 0 the old one.
uniform float look = 0.0;
global uniform float rain_intensity;
// The night aerial review (NightAerial; NIGHT_AERIAL=0 sets the global 0): a helicopter's shaft a
// kilometre or two off - a police patrol seen from the air or across the basin - drew as a solid
// white wedge (the lit-haze look's gain runs the core well over 1, hard-clamped). Far off, between
// `far_from` and `far_to` metres, it saturates softly and falls to `far_gain`: a faint line, with
// its pool on the ground still the bright end. Up close it is as it was.
#ifndef NIGHT_AERIAL_DECLARED
#define NIGHT_AERIAL_DECLARED
global uniform float night_aerial;
#endif
uniform float far_gain = 0.2;
uniform float far_from = 200.0;
uniform float far_to = 1000.0;

float sl_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sl_hash(i), sl_hash(i + vec2(1.0, 0.0)), f.x),
			mix(sl_hash(i + vec2(0.0, 1.0)), sl_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float along = UV.y;
	float fade = pow(1.0 - smoothstep(0.0, length_fade, along), 1.6) * smoothstep(0.0, 0.03, along);
	// Edge-on the cone wall is thin and reads as a hard line; face-on it is the thick of the
	// beam. NORMAL and VIEW are both in view space.
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	float gain = 1.0;
	if (look > 0.5) {
		// The core: face-on the beam is thickest, so the middle of the shaft burns.
		float core = pow(face, 5.0);
		float motes = sl_noise(vec2(UV.x * 26.0, UV.y * 60.0 - TIME * 0.35));
		motes = mix(0.75, 1.35, motes);
		float wet = clamp(rain_intensity, 0.0, 1.0);
		gain = (1.5 + 2.2 * core) * motes * (1.0 + 1.6 * wet);
		// Brighter all the way down: the haze is lit to the ground, not just near the lamp.
		fade = mix(fade, pow(1.0 - along, 0.7) * smoothstep(0.0, 0.03, along), 0.5);
	}
	ALBEDO = tint;
	float a = fade * face * strength * gain * lamp_factor;
	if (night_aerial > 0.5) {
		float far_k = smoothstep(far_from, far_to, length(VERTEX));
		a = mix(clamp(a, 0.0, 1.0), 1.0 - exp(-a * 1.3), far_k) * mix(1.0, far_gain, far_k);
	}
	ALPHA = clamp(a, 0.0, 1.0);
}
