shader_type spatial;
render_mode cull_back;

// The lit crowns of the downtown towers (LandmarkDowntown): the glass lantern on the round
// tower, the blue ellipse, the sail, the stepped pyramid, the lit bands on the slabs. By day
// they are glass or panel like the rest of the tower; after dark they glow, and that glow is what
// a skyline IS at night - a row of crowns, each its own shape and colour, over a field of lit
// windows.
//
// Per vertex, from TowerMesh:
//   COLOR.rgb  the colour this part glows (one mesh carries several: a white lantern with a red
//              beacon ring, a sail with a cooler edge)
//   COLOR.a    how strongly it glows, 0..1 (0 = a dark frame member in the same surface)
//   UV         x metres round the outline, y metres up the part: the rib and band pattern

global uniform float night_factor;
// The sky DayNight publishes; glass by day mirrors it, like building.gdshader's emitted mirror.
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform vec3 origin_shift;
// The skyline's glass by day (building.gdshader has the same): the crown mirrors this hour's sky,
// its clouds, the towers round it and the sun; the ribs are box filtered.
#include "res://shaders/skyline_glass.gdshaderinc"

// What the crown looks like by day: tinted glass or a painted panel.
uniform vec3 day_color : source_color = vec3(0.30, 0.38, 0.46);
uniform float day_metallic : hint_range(0.0, 1.0) = 0.35;
uniform float day_roughness : hint_range(0.0, 1.0) = 0.18;
// How much of the sky the glass carries as its own light by day (see building.gdshader:
// reflect_emit - a mirror does not depend on the light falling on it).
uniform float day_mirror : hint_range(0.0, 1.0) = 0.35;
// Night glow, over white. Above ~1.3 it blooms (the Environment's glow threshold).
uniform float glow_energy = 3.2;
// 0 even glass, 1 vertical ribs (mullions every `rib` metres), 2 horizontal bands.
uniform int pattern = 1;
uniform float rib = 1.6;
// Brighter toward the top of a part (lit from inside, uplit), 0 = flat.
uniform float top_bias : hint_range(0.0, 1.0) = 0.35;
// Height of the part in metres, for the bias above.
uniform float part_height = 20.0;

void fragment() {
	float lit = COLOR.a;
	vec3 glow = COLOR.rgb;
	float frame = 0.0;
	bool sg = sg_on();
	if (pattern == 1) {
		float f = fract(UV.x / rib);
		frame = sg ? sg_line(UV.x - 0.9 * rib, fwidth(UV.x), rib, 0.1 * rib) : step(0.9, f);
	} else if (pattern == 2) {
		float f = fract(UV.y / rib);
		frame = sg ? sg_line(UV.y - 0.82 * rib, fwidth(UV.y), rib, 0.18 * rib) : step(0.82, f);
	}
	// A frame member is metal by day and a dark line at night: the glow is the glass between.
	vec3 albedo = mix(day_color, day_color * 0.45, frame);
	float up = clamp(UV.y / max(part_height, 0.1), 0.0, 1.0);
	float grade = mix(1.0, 0.55 + 0.9 * up, top_bias);
	float night = smoothstep(0.15, 0.85, night_factor);
	vec3 sky = sky_tint.rgb;
	vec3 mirror = mix(vec3(0.10), sky, 0.8) * day_mirror * (1.0 - frame) * (1.0 - night);
	if (sg) {
		// The sky in the crown's glass, as the tower's own glass has it (the old mirror emitted
		// sky_tint's display numbers raw, which Forward+ took for linear: a pale crown).
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 to_frag = normalize(wp - INV_VIEW_MATRIX[3].xyz);
		vec3 refl = reflect(to_frag, wn);
		vec3 sun = normalize(sun_direction);
		vec3 sky_ref = sg_srgb_in(mix(SG_OLD_RIM, SG_OLD_TOP, smoothstep(0.0, 0.55, refl.y))) * sg_sky_ratio(refl, sun);
		sky_ref = sg_clouds(refl, sky_ref, TIME);
		float t_hit;
		vec4 tw = sg_towers(wp + origin_shift, refl, length(fwidth(wp)), length(VERTEX), sky_ref, sun, t_hit);
		sky_ref = mix(sky_ref, tw.rgb, tw.a);
		sky_ref = mix(sg_srgb_in(vec3(0.09, 0.09, 0.10)), sky_ref, smoothstep(-0.22, 0.10, refl.y));
		float fres = pow(1.0 - clamp(-dot(to_frag, wn), 0.0, 1.0), 4.0);
		float sky_now = clamp(sg_luma(sky_tint.rgb) / 0.74, 0.0, 1.5);
		mirror = sky_ref * mix(0.55, 1.6, fres) * sky_now * day_mirror * (1.0 - frame) * (1.0 - night);
		mirror += sg_glint(refl, sun) * (1.0 - tw.a) * day_mirror * 2.0 * (1.0 - frame) * (1.0 - night);
	}
	ALBEDO = mix(albedo, albedo * 0.25, night * lit);
	METALLIC = mix(day_metallic, 0.0, night * lit);
	ROUGHNESS = mix(day_roughness, 0.6, frame);
	SPECULAR = 0.4;
	EMISSION = mirror + glow * lit * glow_energy * grade * night * (1.0 - 0.85 * frame);
}
