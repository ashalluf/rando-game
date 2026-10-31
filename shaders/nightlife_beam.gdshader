shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A premiere's or a club opening's searchlight beam sweeping the sky (SkyBeam), drawn as an open
// cone where volumetric fog cannot draw it (the web, every Quality level below HIGH, and on
// Forward+ HIGH past `near_start` of its length, where the fog's froxels run out). The cone is a
// CylinderMesh scaled to the beam, UV.y running from the lens (0) to the far end (1).
// Haze makes a beam: brightest near the lamp where the air is lit densest, dying away into the
// dark with distance, soft at its silhouette edges, a little warmer and denser in a thick night
// (`haze`, from the depth fog SkyBeam reads).

global uniform float lamp_factor;
uniform vec3 tint = vec3(0.86, 0.9, 1.0);
uniform float strength : hint_range(0.0, 3.0) = 0.6;
// Where along the beam the drawn shaft starts (0 at the lens; Forward+ HIGH hands the first part
// to the volumetric fog).
uniform float near_start : hint_range(0.0, 1.0) = 0.0;
uniform float haze : hint_range(0.0, 3.0) = 1.0;
// How far along the beam (share of its length) it has faded to nothing.
uniform float length_fade : hint_range(0.05, 1.0) = 1.0;
// The night flight pass (NightFlight; NIGHT_FLIGHT=0 sets the global 0): a camera flying past a
// beam saw it as a solid white bar across the frame - a shaft of lit haze is faint when you are
// in it or above it (the few metres of air at its side are all you look through, and the eye is not adapted
// to its source). Seen from under `beam_near_fade` metres it fades toward `beam_near_floor`.
#ifndef NIGHT_FLIGHT_DECLARED
#define NIGHT_FLIGHT_DECLARED
global uniform float night_flight;
#endif
uniform float beam_near_fade = 260.0;
uniform float beam_near_floor = 0.2;

varying flat vec3 lens_world;

void vertex() {
	// The lamp end (UV.y 0: the CylinderMesh's narrow top).
	lens_world = (MODEL_MATRIX * vec4(0.0, 0.5, 0.0, 1.0)).xyz;
}

void fragment() {
	float along = UV.y;
	float fade = pow(1.0 - smoothstep(0.0, length_fade, along), 2.2) * (0.35 + 0.65 * exp(-along * 6.0));
	fade *= smoothstep(near_start * 0.6, near_start + 0.02, along) * smoothstep(0.0, 0.004, along);
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	if (night_flight > 0.5) {
		// Only for a camera in the air over the lamp: from the street, looking up the shaft from
		// its foot, it keeps its look.
		float above = smoothstep(40.0, 110.0, CAMERA_POSITION_WORLD.y - lens_world.y);
		float near_k = mix(beam_near_floor, 1.0, smoothstep(beam_near_fade * 0.12, beam_near_fade, length(VERTEX)));
		fade *= mix(1.0, near_k, above);
	}
	ALBEDO = tint;
	ALPHA = clamp(fade * face * strength * haze * clamp(lamp_factor * 1.4 - 0.2, 0.0, 1.0), 0.0, 1.0);
}
