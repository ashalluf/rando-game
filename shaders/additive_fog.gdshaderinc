// An additive (blend_add) light that writes only ALBEDO leaves ALPHA at 1, and both renderers then
// mix the fog colour into it: albedo * (1 - fog) + fog_colour * fog, added over the WHOLE quad -
// a pale haze-coloured rectangle wherever the light itself is dark (the chase-box bug: the car
// lamps' halo quads, never collapsed by day, drew a grey square round each tail lamp of every
// running car; docs/HANDOFF.md "The pale box round the player's car").
//
// af_cover(light) hands the light back as (rgb, alpha) with the alpha its coverage: ALBEDO x ALPHA
// is exactly the light (the blend), the fog still attenuates it, and the fog colour is added only
// where there is light. No light, nothing drawn. Shader includes use // comments.

const float AF_COVER_GAIN = 64.0;

vec4 af_cover(vec3 light) {
	float m = max(light.r, max(light.g, light.b));
	float a = clamp(m * AF_COVER_GAIN, 0.0, 1.0);
	return vec4(a > 0.0 ? light / a : vec3(0.0), a);
}
