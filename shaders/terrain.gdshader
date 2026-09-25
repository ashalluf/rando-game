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
// Cost: 7 texture fetches a fragment and nine value noises (8 and ten with ground_detail).

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
uniform float dirt_mean_luma = 0.203;
uniform float rock_mean_luma = 0.072;
// Straw on a pale, burnt hillside and on a greener, later-drying one (LINEAR albedo).
uniform vec3 straw_color = vec3(0.175, 0.135, 0.055);
uniform vec3 straw_green_color = vec3(0.120, 0.104, 0.040);
// Chaparral: the brush with the shade between the bushes (LINEAR).
uniform vec3 chaparral_color = vec3(0.045, 0.062, 0.025);
// Decomposed granite and dirt (LINEAR), and how much of the dirt texture's own orange survives.
uniform vec3 dirt_color = vec3(0.170, 0.130, 0.080);
uniform float dirt_keep_hue : hint_range(0.0, 1.0) = 0.25;
// How much bare ground shows between the thinnest grass tufts, up close.
uniform float bare_between : hint_range(0.0, 1.0) = 0.7;
// Rock outcrops, buff sandstone going grey (LINEAR), and how much of the texture's hue stays.
uniform vec3 rock_color = vec3(0.115, 0.102, 0.086);
uniform float rock_keep_hue : hint_range(0.0, 1.0) = 0.15;
// How much of the ground is chaparral, and how much more of it the north-facing slopes carry.
uniform float chaparral_amount : hint_range(0.0, 1.0) = 0.45;
uniform float north_brush : hint_range(0.0, 1.0) = 0.25;
// Single shrubs (sage, buckwheat) dotted through the open grass.
uniform float sage_amount : hint_range(0.0, 1.0) = 0.5;
// Slope (1 - normal.y) where bare dirt starts and has taken over, and where rock does. The
// ranges are steep (median slope 0.14, 31 degrees; 0.30 is the steepest quarter, 0.45 the
// steepest tenth), so most of a hillside stays grass and brush, as the real ones do.
uniform float dirt_slope_start : hint_range(0.0, 1.0) = 0.36;
uniform float dirt_slope_end : hint_range(0.0, 1.0) = 0.56;
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.45;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.66;
// Fire roads and foot trails across the open slopes; 0 turns them off.
uniform float trail_amount : hint_range(0.0, 1.0) = 0.8;
// Brightness swing between one hillside and the next, so a range is never one tile.
uniform float macro_variation : hint_range(0.0, 1.0) = 0.22;
// Metres above sea level the snow starts: the far ground's `snow_line`, keep them equal.
uniform vec3 snow_color = vec3(0.58, 0.60, 0.66);
uniform float snow_line = 1150.0;
// Same second fetch as the road shader, and the same global switch: the grass is sampled again
// rotated and at another scale and cross-faded on slow noise, which kills the visible tiling.
global uniform float ground_detail;

varying vec3 world_pos;
varying vec3 world_nrm;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = MODEL_NORMAL_MATRIX * NORMAL;
}


float hash12t(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoiset(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12t(i), hash12t(i + vec2(1.0, 0.0)), f.x),
		mix(hash12t(i + vec2(0.0, 1.0)), hash12t(i + vec2(1.0, 1.0)), f.x), f.y);
}


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


void fragment() {
	vec2 w = world_pos.xz + world_offset;
	vec3 wn = normalize(world_nrm);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	// +1 on a slope facing north (normal toward -Z), -1 facing south, 0 on the flat.
	float north = -wn.z / max(length(wn.xz), 0.001) * smoothstep(0.02, 0.12, slope);

	// ---- noise: hillside, patch and bush scales ---------------------------------------------
	float hill = vnoiset(w * 0.0028);
	float patchy = vnoiset(w * 0.011) * 0.65 + vnoiset(w * 0.037 + 13.1) * 0.35;
	// Single bushes are ~3 m across: past a metre a pixel they would only sparkle, so they
	// fade to their average there.
	float bush_fade = 1.0 - smoothstep(0.5, 2.0, length(fwidth(w)));
	float bush = mix(0.5, vnoiset(w * 0.29 + 3.7), bush_fade);
	// Tufts and clumps a metre across, faded out sooner still.
	float leaf_fade = 1.0 - smoothstep(0.12, 0.5, length(fwidth(w)));
	float leaf = mix(0.5, vnoiset(w * 0.9 + 51.0), leaf_fade);
	float tuft = bush * 0.6 + leaf * 0.4;

	// ---- grass: the lawn texture's blades recoloured to straw, mottled by the aerial scan ---
	vec2 uv = w / grass_scale;
	vec3 g = texture(grass_albedo, uv).rgb;
	if (ground_detail > 0.5) {
		vec2 uv2 = (mat2(vec2(0.74, -0.67), vec2(0.67, 0.74)) * w) / (grass_scale * 1.61) + vec2(7.3, 2.9);
		float blend = smoothstep(0.32, 0.68, vnoiset(w * 0.021 + 5.0));
		g = mix(g, texture(grass_albedo, uv2).rgb, blend);
	}
	// The blades mip away to one flat tone past a few tens of metres; the aerial scan's worn
	// patches and tufts, at a much larger tile, carry the grain from there out to the LOD ring.
	float mot = clamp(luma(texture(mottle_albedo, w / mottle_scale).rgb) / mottle_mean_luma, 0.4, 1.8);
	float gl = clamp(luma(g) / grass_mean_luma, 0.3, 2.0) * (1.0 + (mot - 1.0) * mottle_amount);
	// Greener where the ground holds its water a little longer: some hillsides, and low down.
	float green = clamp(smoothstep(0.3, 0.75, hill) * 0.8 + (1.0 - smoothstep(60.0, 260.0, world_pos.y)) * 0.25, 0.0, 1.0);
	// Thick and thin tufts, and bare ground between them where the grass is thinnest: without
	// these the mipped blades leave the slope one flat tone from twenty metres out.
	vec3 grass = mix(straw_color, straw_green_color, green * 0.8) * gl * mix(0.78, 1.2, tuft);
	vec2 duv = w / dirt_scale;
	vec3 d = texture(dirt_albedo, duv).rgb;
	vec3 dirt = mix(dirt_color * clamp(luma(d) / dirt_mean_luma, 0.3, 2.0), d * (luma(dirt_color) / dirt_mean_luma), dirt_keep_hue);
	grass = mix(grass, dirt, smoothstep(0.4, 0.25, tuft) * bare_between);

	// ---- chaparral: stands of dark brush, thicker on the shaded side, sage dotted between ---
	// `coverage` is the share of the ground the brush takes here; the threshold is where the
	// patch noise (mean 0.5) leaves about that share below it. A third, finer octave and the
	// bush noise rag the stand's edge so it reads as shrubs, not as camouflage blobs.
	float coverage = chaparral_amount + north * north_brush + (hill - 0.5) * 0.3;
	float th = 0.5 + (coverage - 0.5) * 0.45;
	float frag = patchy * 0.8 + vnoiset(w * 0.12 + 17.0) * 0.2 + (bush - 0.5) * 0.08;
	float brush = smoothstep(th + 0.045, th - 0.045, frag);
	// Gaps between the bushes of a stand, where the straw shows through, and single shrubs out
	// in the open grass.
	brush *= smoothstep(0.12, 0.3, bush);
	brush = max(brush, mix(0.05, smoothstep(0.76, 0.84, bush), bush_fade) * sage_amount);
	// Single bushes with shade between them, leaf clumps on those, the blade grain on those.
	vec3 chap = chaparral_color * mix(0.45, 1.3, bush) * mix(0.5, 1.4, leaf) * (0.65 + 0.35 * gl);
	grass = mix(grass, chap, brush);

	// ---- dirt: steep cuts and road banks, the odd bare patch, trails -----------------------
	float bare = smoothstep(dirt_slope_start, dirt_slope_end, slope + (patchy - 0.5) * 0.3);
	// Trails: one contour of a slow noise, about a metre wide, only on some hillsides and off the
	// steep ground. fwidth keeps it a line rather than a stair of pixels from far off.
	float tn = vnoiset(w * 0.0065 + 41.0);
	float trail = 1.0 - smoothstep(0.0035, 0.0035 + fwidth(tn) * 1.5, abs(tn - 0.5));
	trail *= smoothstep(0.55, 0.7, vnoiset(w * 0.0021 + 7.0)) * (1.0 - smoothstep(0.18, 0.30, slope)) * trail_amount;
	bare = max(bare, trail * 0.9);
	vec3 albedo = mix(grass, dirt, bare);

	// ---- rock: outcrops on the steepest faces, and a few breaking through on the ridges ----
	vec2 ruv = w / rock_scale;
	vec3 r = texture(rock_albedo, ruv).rgb;
	vec3 rock = mix(rock_color * clamp(luma(r) / rock_mean_luma, 0.3, 2.2), r * (luma(rock_color) / rock_mean_luma), rock_keep_hue);
	float crag = vnoiset(w * 0.021 + 29.0);
	float rocky = smoothstep(rock_slope_start, rock_slope_end, slope + (crag - 0.5) * 0.22);
	rocky = max(rocky, smoothstep(0.78, 0.86, crag * 0.7 + patchy * 0.3) * smoothstep(0.10, 0.22, slope));
	albedo = mix(albedo, rock, rocky);

	// ---- hillside-scale variation: nothing reads as one tile from across the valley --------
	albedo *= 1.0 + (hill - 0.5) * 2.0 * macro_variation + (patchy - 0.5) * macro_variation * 0.6;

	// Snow above the far ground's snow line, and not on the near-vertical faces.
	float snow = smoothstep(snow_line, snow_line + 270.0, world_pos.y) * (1.0 - smoothstep(0.45, 0.8, slope));
	ALBEDO = mix(albedo, snow_color, snow);

	vec3 nm = texture(grass_normal, uv).rgb;
	nm = mix(nm, texture(dirt_normal, duv).rgb, bare);
	nm = mix(nm, texture(rock_normal, ruv).rgb, rocky);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(mix(0.8, 1.0, bare), 1.3, rocky) * (1.0 - snow * 0.7);
	ROUGHNESS = mix(mix(mix(0.95, 0.9, brush), 0.93, bare), mix(0.82, 0.62, snow), max(rocky, snow));
}
