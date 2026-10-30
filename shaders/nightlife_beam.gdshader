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

void fragment() {
	float along = UV.y;
	float fade = pow(1.0 - smoothstep(0.0, length_fade, along), 2.2) * (0.35 + 0.65 * exp(-along * 6.0));
	fade *= smoothstep(near_start * 0.6, near_start + 0.02, along) * smoothstep(0.0, 0.004, along);
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = tint;
	ALPHA = clamp(fade * face * strength * haze * clamp(lamp_factor * 1.4 - 0.2, 0.0, 1.0), 0.0, 1.0);
}
