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
// to its source). Seen from under `beam_near_fade` metres it fades toward `beam_near_floor`, and from the air
// it carries `beam_air_gain` of its strength.
#ifndef NIGHT_FLIGHT_DECLARED
#define NIGHT_FLIGHT_DECLARED
global uniform float night_flight;
#endif
uniform float beam_near_fade = 600.0;
uniform float beam_near_floor = 0.15;
// Seen from the air the shaft stands against the lit city, not the black sky, and the eye has
// nothing to adapt to: it carries this share of its street-level strength.
uniform float beam_air_gain = 0.4;
// The night aerial review (NightAerial; NIGHT_AERIAL=0 sets the global 0): from the air and far off
// (`beam_far_from`..`beam_far_to` metres) the cone's two walls still summed to a solid white bar; a
// shaft of lit haze a couple of kilometres away is a faint pale line. It falls to `beam_far_gain`.
#ifndef NIGHT_AERIAL_DECLARED
#define NIGHT_AERIAL_DECLARED
global uniform float night_aerial;
#endif
uniform float beam_far_gain = 0.35;
uniform float beam_far_from = 700.0;
uniform float beam_far_to = 2200.0;

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
		fade *= mix(1.0, near_k * beam_air_gain, above);
		if (night_aerial > 0.5) {
			fade *= mix(1.0, beam_far_gain, above * smoothstep(beam_far_from, beam_far_to, length(VERTEX)));
		}
	}
	ALBEDO = tint;
	ALPHA = clamp(fade * face * strength * haze * clamp(lamp_factor * 1.4 - 0.2, 0.0, 1.0), 0.0, 1.0);
}
