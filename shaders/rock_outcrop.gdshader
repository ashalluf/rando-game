shader_type spatial;
render_mode cull_back;

// The hills' real rock (RockKit, scripts/world/rock_kit.gd): photoscanned Poly Haven cliffs and
// boulders, from the boulders by a hill road to tors tens of metres high on the crests.
//
// One shader for every distance. Near (a FULL or LOD chunk drew the real terrain under the rock,
// INSTANCE_CUSTOM.r 1) the rock stays where the CPU put it, on MacroMap.height_at(). Past the
// streamed chunks the visible ground is the horizon plane (macro_ground.gdshader), which runs
// tens of metres under the real ground on a ridge, so the rock is moved as a whole onto the
// plane's drawn triangles under its origin, exactly as far_canopy.gdshader seats the far
// planting (the same include, the same plane uniforms, CityStreamer keeps them current).
//
// Colour: the scans are Namaqualand granite, orange-brown. The hills here are buff sandstone and
// grey granite, so the scan's albedo is kept only as LUMINANCE (its cracks, lichen and grain, as
// a ratio to the scan's own mean) and recoloured to the hills' rock palette per instance
// (INSTANCE_CUSTOM.g, 0 buff sandstone .. 1 grey granite). On top of it: desert varnish (dark
// streaks running down the steep faces), dust and dry grass on what faces the sky, and the
// ground's dirt over the foot, so a rock sits IN the hill rather than on it. Linear on both
// renderers (color_space.gdshaderinc).
#include "res://shaders/macro_relief.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// The scan's ARM map: R ambient occlusion, G roughness.
uniform sampler2D arm_tex : filter_linear_mipmap, repeat_enable;
// The scan's mean albedo luminance (linear), measured by RockKit, so the recolour keeps the
// scan's detail as a ratio round 1.
uniform float scan_mean = 0.2;
// How much of the scan's light and dark survives (1 the scan's own contrast).
uniform float scan_contrast = 1.15;
// The rock palette, linear: buff sandstone, grey granite, and the dark of desert varnish.
uniform vec3 sandstone_color = vec3(0.150, 0.112, 0.074);
uniform vec3 granite_color = vec3(0.118, 0.108, 0.094);
uniform vec3 varnish_color = vec3(0.055, 0.045, 0.036);
uniform float varnish_amount : hint_range(0.0, 1.0) = 0.7;
// What settles on the rock: the hills' dirt and their straw (hill_splat.gdshaderinc's numbers).
uniform vec3 dust_color = vec3(0.205, 0.176, 0.133);
uniform vec3 straw_color = vec3(0.200, 0.158, 0.076);
uniform float dust_amount : hint_range(0.0, 1.0) = 0.6;
// The foot: within this share of the rock's height the ground's dirt creeps up its faces.
uniform float foot_share : hint_range(0.0, 0.5) = 0.12;
// The mesh's own height (its AABB), set by RockKit.
uniform float mesh_height = 5.0;
// The scan's normal map at a finer tiling over the base one, faded out by `detail_reach` metres.
uniform float detail_tiling = 5.0;
uniform float detail_reach = 60.0;
// The welded mesh (RockKit.mid_mesh): no UVs, so no scan maps; the hills' own tileable rock
// (terrain.gdshader's outcrop texture) is laid triplanar in true world space instead, `tile_size`
// metres a tile, as luminance round its mean.
uniform bool far_mode = false;
uniform sampler2D tile_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_mean = 0.2;
uniform float tile_size = 9.0;
// The welded mesh's brightness against the scan's, and how much dust settles on it.
uniform float far_tone = 0.78;
uniform float far_dust = 0.3;

// Seated on the far plane where INSTANCE_CUSTOM.r says no chunk drew the real ground (RockFar's
// materials); off for the rocks a chunk's batch draws, which always stand on its terrain.
uniform bool seat = false;
// The far plane's own numbers (far_canopy.gdshader's, set by CityStreamer).
uniform float plane_y = 0.0;
uniform vec2 plane_origin = vec2(0.0);
uniform float plane_half = 7000.0;
uniform float plane_step = 43.61;
uniform float edge_start = 5040.0;
uniform float edge_end = 6860.0;
global uniform vec4 sky_tint;
// The horizon plane's layered distance haze (macro_relief.gdshaderinc's range_haze_*), as the far
// canopy takes it: without it every far tor was unhazed against hazed slopes, a field of brown
// flecks over each range from the air (aerial review). AerialReview turns it off (the A/B).
uniform bool aerial_haze = true;
// And past `aerial_blend` metres a far tor loses up to `aerial_blend_max` of its colour and of its
// light-and-dark: a warm orange crag in full renderer light on a slope the plane paints and hazes
// to a pale grey-beige, measured (177, 164, 135) on (168, 164, 145) with a spread of +-22 per
// channel, read as one fleck per tor however much haze lay on both. Its shape stays: the crags
// still break the skyline, they just stop being confetti.
uniform vec2 aerial_blend = vec2(1100.0, 3600.0);
uniform float aerial_blend_max : hint_range(0.0, 1.0) = 0.75;

varying vec3 world_pos;
varying vec3 world_nrm;
varying float foot;
varying float tone;
varying float rim;
varying float cam_dist;
varying float rhaze;


float corner_height(vec2 xz, vec3 cam) {
	vec4 m;
	vec2 mg;
	float wet;
	float d;
	float lift = far_ground_lift(vec3(xz.x, plane_y, xz.y), cam, m, mg, wet, d);
	return lift - far_ground_sink(d, wet);
}


// The plane's drawn surface at `xz` (far_canopy.gdshader's plane_height(), line for line).
float plane_height(vec2 xz, vec3 cam) {
	vec2 g = (xz - (plane_origin - vec2(plane_half))) / plane_step;
	vec2 i = clamp(floor(g), vec2(0.0), vec2(round(2.0 * plane_half / plane_step) - 1.0));
	vec2 f = clamp(g - i, vec2(0.0), vec2(1.0));
	vec2 c0 = plane_origin - vec2(plane_half) + i * plane_step;
	float h01 = corner_height(c0 + vec2(0.0, plane_step), cam);
	float h10 = corner_height(c0 + vec2(plane_step, 0.0), cam);
	if (f.x + f.y < 1.0) {
		float h00 = corner_height(c0, cam);
		return h00 + f.x * (h10 - h00) + f.y * (h01 - h00);
	}
	float h11 = corner_height(c0 + vec2(plane_step), cam);
	return h11 + (1.0 - f.x) * (h01 - h11) + (1.0 - f.y) * (h10 - h11);
}


float rhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float rnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rhash(i), rhash(i + vec2(1.0, 0.0)), u.x), mix(rhash(i + vec2(0.0, 1.0)), rhash(i + vec2(1.0, 1.0)), u.x), u.y);
}


void vertex() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float real = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	float shift = 0.0;
	if (seat && real < 0.999) {
		// INSTANCE_CUSTOM.b is how deep the CPU sank the rock's origin under the real ground (/100).
		float sink = INSTANCE_CUSTOM.b * 100.0;
		shift = (plane_y + plane_height(origin.xz, cam) - sink - origin.y) * (1.0 - real);
	}
	// The tone: INSTANCE_CUSTOM.g where the planner rolled one, else a hash of the true origin.
	vec2 wo = origin.xz + world_offset;
	tone = seat ? INSTANCE_CUSTOM.g : fract(sin(dot(floor(wo * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	// Where the ground meets the rock in its own units (the origin's sink over its y scale).
	float g = INSTANCE_CUSTOM.b * 100.0 / max(length(MODEL_MATRIX[1].xyz), 0.01);
	foot = 1.0 - smoothstep(g, g + foot_share * mesh_height, VERTEX.y);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, shift, 0.0);
	// INSTANCE_CUSTOM.a 0: collapsed (a far cell's copy of a tor its near cell is drawing).
	if (seat && INSTANCE_CUSTOM.a < 0.5) {
		VERTEX = vec3(0.0);
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	cam_dist = length(world_pos - cam);
	rhaze = aerial_haze ? range_haze_amount(cam_dist, world_pos.y) : 0.0;
	rim = smoothstep(edge_start, edge_end, length(origin.xz - cam.xz));
}


void fragment() {
	// True world XZ, so nothing on the rock slides at an origin shift.
	vec3 wp = world_pos + vec3(world_offset.x, 0.0, world_offset.y);
	float detail;
	vec3 arm;
	if (far_mode) {
		vec3 an = abs(normalize(world_nrm));
		vec3 w = an * an * an * an;
		w /= (w.x + w.y + w.z);
		vec3 tp = wp / tile_size;
		vec3 t = cs_in(texture(tile_tex, tp.zy).rgb) * w.x + cs_in(texture(tile_tex, tp.xz).rgb) * w.y + cs_in(texture(tile_tex, tp.xy).rgb) * w.z;
		detail = min(pow(max(dot(t, vec3(0.2126, 0.7152, 0.0722)) / max(tile_mean, 1e-3), 0.0), 1.3), 1.8);
		// Far off a crag is mostly its shaded faces and cracks: a little darker than the scan reads
		// close up, or a range's crags drew as pale flecks against the straw.
		detail *= (0.85 + 0.3 * rnoise(wp.xz * 0.05 + vec2(wp.y * 0.11, 3.0))) * far_tone;
		arm = vec3(1.0, 1.0, 0.0);
	} else {
		vec3 scan = cs_in(texture(albedo_tex, UV).rgb);
		float lum = dot(scan, vec3(0.2126, 0.7152, 0.0722));
		// Capped: the scan's atlas has pale gaps between its islands, which a seam samples.
		detail = min(pow(max(lum / max(scan_mean, 1e-3), 0.0), scan_contrast), 1.8);
		arm = texture(arm_tex, UV).rgb;
	}
	vec3 base = mix(sandstone_color, granite_color, smoothstep(0.25, 0.75, tone));
	// Each rock a little lighter or darker, warmer or cooler.
	base *= mix(0.86, 1.12, fract(tone * 7.31));
	vec3 col = base * detail;
	vec3 n = normalize(world_nrm);
	float steep = 1.0 - smoothstep(0.35, 0.8, n.y);
	// Desert varnish: dark streaks down the steep faces, long in y, narrow across.
	float across = dot(wp.xz, normalize(vec2(n.z, -n.x) + vec2(1e-4)));
	float streak = rnoise(vec2(across * 0.55, wp.y * 0.045)) * 0.65 + rnoise(vec2(across * 1.7, wp.y * 0.12)) * 0.35;
	float varnish = smoothstep(0.55, 0.85, streak) * steep * varnish_amount;
	col = mix(col, varnish_color * detail, varnish);
	// Dust and dry grass on what faces the sky, in patches.
	float patch = rnoise(wp.xz * 0.35) * 0.6 + rnoise(wp.xz * 1.3) * 0.4;
	float dust = smoothstep(0.55, 0.9, n.y) * smoothstep(0.3, 0.7, patch) * (far_mode ? far_dust : dust_amount);
	vec3 settle = mix(dust_color, straw_color, smoothstep(0.55, 0.85, patch));
	col = mix(col, settle * mix(0.8, 1.1, detail), dust);
	// The ground's dirt over the foot.
	col = mix(col, dust_color * mix(0.75, 1.0, detail), clamp(foot, 0.0, 1.0) * 0.85);
	// The scan's crevices darken a little more than its texture says.
	col *= mix(0.7, 1.0, arm.r);
	if (aerial_haze && far_mode) {
		float fb = smoothstep(aerial_blend.x, aerial_blend.y, cam_dist) * aerial_blend_max;
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		// The rock's mean tone (its palette under the detail's mean of ~1), cooled to the slope's.
		float l_mean = dot(base, vec3(0.2126, 0.7152, 0.0722));
		vec3 grey = vec3(mix(l, l_mean, 0.6)) * vec3(1.06, 1.0, 0.86);
		col = mix(col, grey, fb);
	}
	if (!far_mode) {
		vec3 nm = texture(normal_tex, UV).rgb;
		float near = 1.0 - smoothstep(detail_reach * 0.5, detail_reach, cam_dist);
		if (near > 0.0) {
			vec3 nd = texture(normal_tex, UV * detail_tiling).rgb;
			nm = normalize(vec3(nm.xy + (nd.xy - 0.5) * 0.8 * near, nm.z));
		}
		NORMAL_MAP = nm;
	}
	ALBEDO = cs_out(col) * (1.0 - rim);
	EMISSION = cs_out(cs_srgb_to_linear(sky_tint.rgb)) * rim;
	ALBEDO *= 1.0 - rhaze;
	EMISSION += cs_out(range_haze_color(cs_srgb_to_linear(sky_tint.rgb))) * (rhaze * (1.0 - rim));
	ROUGHNESS = mix(0.82, 1.0, arm.g) * mix(1.0, 0.92, varnish);
	SPECULAR = 0.35;
}
