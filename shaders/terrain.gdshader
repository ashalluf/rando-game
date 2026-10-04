shader_type spatial;

// Hills: a Southern-California hillside in late summer. Four grounds, mixed per pixel from the
// slope, which way the slope faces, the height and a few octaves of world-space noise:
//   - tawny dry grass on the open slopes (the lawn texture's blades recoloured to straw, with
//     the aerial scan's light and dark as a large-tile mottle), paler or more olive from one
//     hillside to the next
//   - dark olive chaparral in ragged stands, far thicker on the north-facing slopes (in the
//     real hills the shaded side is brush and the sunny side is grass), and single shrubs
//     dotted through the grass
//   - bare dirt / decomposed granite on the steep cuts and road banks, and on a few trails
//   - rock outcrops on the steepest faces, breaking through the grass here and there
// Snow only above `snow_line`, the same line the far ground (macro_ground.gdshader) uses.
// Textures and noise are in TRUE world XZ (`world_offset`, pushed by CityStreamer as it does
// for the far ground), so nothing jumps when the origin re-centres. Layer colours are LINEAR.
// Which patch is which is hill_splat.gdshaderinc, shared with the hill shells (the grass and
// brush understory grown out of this paint near the camera) and mirrored by HillPlanting.
// Cost: 7 texture fetches a fragment and nine value noises (8 and ten with ground_detail), two
// of them with their derivatives for the brush canopy's relief, two orders of erosion noise
// (16 cells each, faded out once a gully is under a few pixels) and, with ground_detail, the
// shrub crowns (four cells, eight hashes).

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mottle_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// How far the scene's origin has been shifted (CityStreamer sets it).
uniform vec2 world_offset = vec2(0.0);
// Metres per tile of each ground.
uniform float grass_scale = 3.5;
// The aerial grass-and-gravel scan, only its light and dark, at a big tile over the blades.
uniform float mottle_scale = 13.0;
uniform float mottle_amount : hint_range(0.0, 1.0) = 1.0;
uniform float dirt_scale = 4.5;
uniform float rock_scale = 7.0;
// Each texture's mean luminance (linear), so recolouring keeps its detail at the colour asked.
uniform float grass_mean_luma = 0.145;
uniform float mottle_mean_luma = 0.126;
// (hill_shells.gdshader keeps copies of grass_scale, mottle_scale and the two mean lumas, and
// the same two textures: keep them equal.)
uniform float dirt_mean_luma = 0.203;
uniform float rock_mean_luma = 0.072;
// How much of the dirt texture's own orange survives (dirt_color is the splat's).
uniform float dirt_keep_hue : hint_range(0.0, 1.0) = 0.25;
// How much bare ground shows between the thinnest grass tufts, up close.
uniform float bare_between : hint_range(0.0, 1.0) = 0.7;
// How much of the rock texture's hue stays (rock_color is the splat's).
uniform float rock_keep_hue : hint_range(0.0, 1.0) = 0.15;
// Metres of canopy relief a stand of brush has (its bushes and the gaps between them), and of
// leaf clumps on the bushes. They go into the normal, which is what makes brush read as bushes
// from across a canyon instead of a dark stain on a smooth slope.
uniform float brush_relief = 1.1;
uniform float leaf_relief = 0.3;
// How steeply a shrub crown's flanks turn from the light (slope at its rim).
uniform float crown_relief = 1.3;
// How hard the ground textures' own normal maps bend the light.
uniform float detail_normal : hint_range(0.0, 2.0) = 1.0;
// The gullies finer than the height field's own (shaders/erosion.gdshaderinc): metres deep
// for the first order, metres between its gullies, and how much darker a gully floor is.
uniform float erosion_amp = 7.0;
uniform float erosion_cell = 55.0;
uniform float erosion_shade : hint_range(0.0, 1.0) = 0.2;
// (dirt_color, rock_color, drain_shade, macro_variation, snow_color and snow_line are the splat's,
// hill_splat.gdshaderinc, which the horizon plane reads too.)
// Same second fetch as the road shader, and the same global switch: the grass is sampled again
// rotated and at another scale and cross-faded on slow noise, which kills the visible tiling.
global uniform float ground_detail;

#include "res://shaders/hill_splat.gdshaderinc"
#include "res://shaders/erosion.gdshaderinc"
// Linear on both renderers: every texture sample through cs_in(), the albedo out through cs_out().
// On Compatibility the textures arrived as raw sRGB and the luma ratios below (against LINEAR
// means) came out two to three times too bright, then clamped - the web's hills were paler than
// the Mac's and nothing like the horizon plane beside them.
#include "res://shaders/color_space.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_nrm;
varying float drain;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = MODEL_NORMAL_MATRIX * NORMAL;
	drain = COLOR.g * 2.0 - 1.0;
}


// A tangent-space normal map sampled in world XZ (u along +X, v along +Z), as the slope it
// describes: d(height)/dx, d(height)/dz. Only .xy is read and z rebuilt, as the renderer does,
// because a normal map imported compressed keeps two channels.
vec2 nm_slope(vec3 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.04));
	return -xy / z;
}


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


void fragment() {
	vec2 w = world_pos.xz + world_offset;
	vec3 wn = normalize(world_nrm);
	// +1 on a slope facing north (normal toward -Z), -1 facing south, 0 on the flat.
	vec2 aspect = hill_aspect(wn);
	float slope = aspect.x;
	float north = aspect.y;
	// The fine gullies: on the flanks, not on the summits, benches and valley floors.
	vec2 fall = -wn.xz / max(wn.y, 0.25);
	// Off with ground_detail (the web, and below MEDIUM), like the second grass fetch.
	vec3 ero = vec3(0.0);
	if (ground_detail > 0.5) {
		ero = erosion_detail(w, fall, erosion_amp * smoothstep(0.08, 0.45, length(fall)), erosion_cell, length(fwidth(w)));
	}

	// ---- noise: hillside, patch and bush scales ---------------------------------------------
	vec2 broad = hill_broad(w);
	float hill = broad.x;
	float patchy = broad.y;
	// Single bushes are ~3 m across: past a metre a pixel they would only sparkle, so they
	// fade to their average there.
	// (A value-noise cell under ~3 pixels aliases into a grid of squares, so both fade by then.)
	float bush_fade = hill_bush_fade(length(fwidth(w)));
	vec3 bush_n = noisedt(w * 0.29 + 3.7);
	float bush = mix(0.5, bush_n.x, bush_fade);
	// Tufts and clumps a metre across, faded out sooner still.
	float leaf_fade = hill_fine_fade(length(fwidth(w)));
	vec3 leaf_n = noisedt(w * 0.9 + 51.0);
	float leaf = mix(0.5, leaf_n.x, leaf_fade);
	float tuft = bush * 0.6 + leaf * 0.4;

	// ---- grass: the lawn texture's blades recoloured to straw, mottled by the aerial scan ---
	vec2 uv = w / grass_scale;
	vec3 g = cs_in(texture(grass_albedo, uv).rgb);
	if (ground_detail > 0.5) {
		vec2 uv2 = (mat2(vec2(0.74, -0.67), vec2(0.67, 0.74)) * w) / (grass_scale * 1.61) + vec2(7.3, 2.9);
		float blend = smoothstep(0.32, 0.68, vnoiset(w * 0.021 + 5.0));
		g = mix(g, cs_in(texture(grass_albedo, uv2).rgb), blend);
	}
	// The blades mip away to one flat tone past a few tens of metres; the aerial scan's worn
	// patches and tufts, at a much larger tile, carry the grain from there out to the LOD ring.
	float mot = clamp(luma(cs_in(texture(mottle_albedo, w / mottle_scale).rgb)) / mottle_mean_luma, 0.4, 1.8);
	float gl = clamp(luma(g) / grass_mean_luma, 0.3, 2.0) * (1.0 + (mot - 1.0) * mottle_amount);
	// Greener where the ground holds its water a little longer: some hillsides, and low down.
	float green = clamp(smoothstep(0.3, 0.75, hill) * 0.8 + (1.0 - smoothstep(60.0, 260.0, world_pos.y)) * 0.25, 0.0, 1.0);
	// Thick and thin tufts, and bare ground between them where the grass is thinnest: without
	// these the mipped blades leave the slope one flat tone from twenty metres out.
	vec3 grass = mix(straw_color, straw_green_color, green * 0.8) * gl * mix(0.78, 1.2, tuft);
	vec2 duv = w / dirt_scale;
	vec3 d = cs_in(texture(dirt_albedo, duv).rgb);
	vec3 dirt = mix(dirt_color * clamp(luma(d) / dirt_mean_luma, 0.3, 2.0), d * (luma(dirt_color) / dirt_mean_luma), dirt_keep_hue);
	// The dirt between the tufts: a narrow cut of the tuft noise, widened by what has faded out of
	// it and by how fast it changes across a pixel - cut sharp from the air, the half-resolved
	// cells drew a grid of brown squares across every grassy bench.
	float tuft_aa = fwidth(tuft) + (1.0 - leaf_fade) * 0.12 + (1.0 - bush_fade) * 0.2;
	grass = mix(grass, dirt, smoothstep(0.4 + tuft_aa, 0.25 - tuft_aa, tuft) * bare_between);

	// ---- chaparral: stands of dark brush, thicker on the shaded side, sage dotted between ---
	// `coverage` is the share of the ground the brush takes here; the threshold is where the
	// patch noise (mean 0.5) leaves about that share below it. A third, finer octave and the
	// bush noise rag the stand's edge so it reads as shrubs, not as camouflage blobs.
	// The stands follow the land, not a blob noise: brush fills the gullies and the north faces,
	// the grass holds the gentle ground and the sunny side, and the patch noise only rags the
	// edge, with most of its weight at the scale of single bushes.
	// (hill_splat.gdshaderinc: the same maths the shells and HillPlanting use.) Clumps of bushes,
	// 8 m across, which still read from across a canyon once the single bushes have faded to
	// their average, then the gaps between the bushes of a stand, where the straw shows
	// through, and single shrubs out in the open grass.
	float mid_fade = hill_mid_fade(length(fwidth(w)));
	// The stand's own 1.1 m octave: the leaf clumps' noise, faded sooner (hill_fine_fade()).
	float fine_fade = leaf_fade;
	float fine = leaf;
	float clump = mix(0.5, vnoiset(w * 0.12 + 17.0), mid_fade);
	float th = hill_stand_threshold(slope, north, drain, hill);
	// Shrub crowns 2.6 m apart: a stand's edge runs round them, and inside it they are lit as
	// domes with shade between them. Gone to their average once one is under a few pixels.
	// Off with ground_detail (the web, below MEDIUM): eight hashes a pixel, and there the edge
	// runs along the plain stand noise (HillPlanting plants by the crowned edge, a crown's width
	// off at most).
	// Full to ~40 m, gone by ~120 m (720 rows; twice that on the Mac): resolved further out,
	// the jittered domes read as bubble wrap across a canyon.
	float crown_fade = (1.0 - smoothstep(0.06, 0.2, length(fwidth(w)))) * step(0.5, ground_detail);
	vec3 crowns = vec3(CROWN_MEAN, 0.0, 0.0);
	if (crown_fade > 0.0) {
		crowns = hill_crowns(w);
	}
	float stand = hill_stand(th, hill_stand_crowned(hill_stand_noise(patchy, clump, bush, fine), crowns.x, crown_fade), bush, hill_stand_edge(fine_fade, bush_fade, mid_fade));
	float sage = hill_sage(bush, bush_fade);
	float brush = max(stand, sage);
	// Crowns with shade between them, leaf clumps on those, the blade grain on those, and the
	// clumps of bushes that still read from across a canyon once the crowns are gone.
	// (Both tones average ~0.88, so a stand keeps its brightness as the crowns fade out.)
	float crown_tone = mix(mix(0.45, 1.3, bush), mix(0.64, 1.24, crowns.x) * mix(0.85, 1.12, bush), crown_fade);
	vec3 chap = mix(chaparral_color, sage_color, smoothstep(-0.05, 0.05, sage - stand))
		* crown_tone * mix(0.5, 1.4, leaf) * mix(0.72, 1.22, clump) * (0.65 + 0.35 * gl);
	grass = mix(grass, chap, brush);

	// ---- dirt: steep cuts and road banks, the odd bare patch, trails -----------------------
	// Scree fans down the steep gullies; trails, one contour of a slow noise about a metre wide.
	float tn = vnoiset(w * 0.0065 + 41.0);
	float trail = hill_trail(tn, fwidth(tn), vnoiset(w * 0.0021 + 7.0), slope);
	float bare = hill_bare(slope, patchy, drain, trail);
	vec3 albedo = mix(grass, dirt, bare);

	// ---- rock: outcrops on the steepest faces, and a few breaking through on the ridges ----
	vec2 ruv = w / rock_scale;
	vec3 r = cs_in(texture(rock_albedo, ruv).rgb);
	vec3 rock = mix(rock_color * clamp(luma(r) / rock_mean_luma, 0.3, 2.2), r * (luma(rock_color) / rock_mean_luma), rock_keep_hue);
	float crag = vnoiset(w * 0.021 + 29.0);
	float rocky = hill_rocky(slope, crag, patchy, drain, bush);
	albedo = mix(albedo, rock, rocky);

	// ---- the drainage: dark canyons, lighter spur crests -------------------------------------
	albedo *= mix(1.0, 1.0 - drain_shade, smoothstep(0.15, 0.9, drain)) * (1.0 + drain_shade * 0.3 * smoothstep(0.2, 0.8, -drain));
	albedo *= 1.0 - erosion_shade * clamp(ero.z, -0.5, 1.0);

	// ---- hillside-scale variation: nothing reads as one tile from across the valley --------
	albedo *= 1.0 + (hill - 0.5) * 2.0 * macro_variation + (patchy - 0.5) * macro_variation * 0.6;

	// Snow above the far ground's snow line, and not on the near-vertical faces.
	float snow = smoothstep(snow_line, snow_line + 270.0, world_pos.y) * (1.0 - smoothstep(0.45, 0.8, slope));
	ALBEDO = cs_out(mix(albedo, snow_color, snow));

	// ---- the surface's own relief -----------------------------------------------------------
	// The terrain mesh has no UVs and so no tangents, and a NORMAL_MAP without tangents does
	// nothing: every hillside was lit as smooth plastic between its 4 m vertices. The detail is
	// worked out here instead as slopes in world XZ - the ground textures' normal maps, and the
	// brush canopy's own bumps from the same noise that places the bushes - and added to the
	// mesh normal as a height field would add them.
	vec2 ds = nm_slope(texture(grass_normal, uv).rgb) * 0.7 * (1.0 - brush);
	ds = mix(ds, nm_slope(texture(dirt_normal, duv).rgb), bare);
	ds = mix(ds, nm_slope(texture(rock_normal, ruv).rgb) * 1.3, rocky);
	// A normal map's slopes are dimensionless, so its tile size does not enter.
	ds *= detail_normal;
	// Bushes: a canopy brush_relief high over the gaps, leaf clumps on top, only in the stands.
	vec2 canopy = (bush_n.yz * 0.29 * brush_relief * bush_fade + leaf_n.yz * 0.9 * leaf_relief * leaf_fade
		- crowns.yz * crown_relief * crown_fade * step(0.001, crowns.x))
		* brush * (1.0 - bare) * (1.0 - rocky);
	ds = (ds + canopy) * (1.0 - snow * 0.7) + ero.xy;
	float ny = max(wn.y, 0.25);
	vec3 n = normalize(wn / ny - vec3(ds.x, 0.0, ds.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(mix(mix(0.95, 0.9, brush), 0.93, bare), mix(0.82, 0.62, snow), max(rocky, snow));
}
