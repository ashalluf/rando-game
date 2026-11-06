shader_type spatial;
render_mode cull_back, shadows_disabled;

// Lit commercial signage: backlit fascia lightboxes, projecting blade signs, channel letters
// and neon tubes. By day this is painted plastic; after dark the same surface glows.
//
// The switch is the lamp_factor shader global that DayNight publishes, which is
// max(night_factor, weather_darken * 0.85) - exactly what shaders/light_pool.gdshader reads.
// So a city covered in signage costs nothing at noon, lights itself at dusk, and lights itself
// in a storm at midday too, all without a single OmniLight. A shopfront-per-light city would
// never render.
//
// Note: shader files use // comments. A # or ## line here is a syntax error and Godot falls
// back to a blank white material, which looks like a missing texture rather than a broken
// shader.

global uniform float lamp_factor;

// Emission while the sign is "off" (daylight). Real plastic lightboxes are lit in the day too,
// just invisibly, so a touch of this keeps them from reading as grey panels at noon.
uniform float day_emission : hint_range(0.0, 2.0) = 0.10;
// Emission once lamp_factor reaches 1. Deliberately over 1 so the glow buffer picks it up and
// the sign blooms instead of just being a bright quad.
uniform float night_emission : hint_range(0.0, 16.0) = 2.6;
// How much of the sign colour shows as paint. A backlit box wants all of it; a glass tube
// wants almost none, because an unlit neon tube is clear glass, not a coloured stick.
uniform float albedo_mix : hint_range(0.0, 1.0) = 1.0;
// The off-white a tube falls back to as albedo_mix goes to zero.
uniform vec3 off_color : source_color = vec3(0.80, 0.80, 0.82);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.35;
// Lifts the sign a touch as it comes on, so a lit box does not look like a dark box with a
// glow stuck on it.
uniform float lit_albedo : hint_range(0.0, 2.0) = 0.45;

void fragment() {
	// COLOR is the per-instance colour out of the MultiMesh, so one mesh and one material
	// cover every sign in the chunk and the whole plaza is a single draw call.
	vec3 c = COLOR.rgb;
	float lit = clamp(lamp_factor, 0.0, 1.0);
	ALBEDO = mix(off_color, c, albedo_mix) * (1.0 + lit_albedo * lit);
	ROUGHNESS = base_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.45;
	EMISSION = c * (day_emission + night_emission * lit);
}
