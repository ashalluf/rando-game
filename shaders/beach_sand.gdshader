shader_type spatial;

// The beach (CityChunk._build_sand): the sand set as PropFactory.pbr("sand") laid it, plus the
// swash. Every wave the ocean breaks (shaders/surf.gdshaderinc) arrives here as a bore and runs
// up the sand as a thin sheet of water - fast up, slowing, then draining back - with a lace of
// foam along its edge, and leaves the sand behind it dark and glossy for a few seconds while the
// water soaks away. The same model, the same TIME and the same globals as the waves, so a swash
// starts the moment its bore arrives and the big waves of a set run up furthest.
//
// The mesh tells this shader where the sea is: UV2.x is the metres landward of the waterline
// (MacroMap.coast_x(), negative under the water) and UV2.y the beach's width; the sand is laid
// in rows of constant z running inland along +x, so the waterline point of a row is straight
// seaward along -x. COLOR is the static wet/dry banding (CityChunk.SAND_TONES).
//
// The thin sheet mirrors the sky the way the sea does: its reflection is EMITTED by fresnel
// against the published sky colour (the renderer's own reflection is cubemap-only on the web and
// blurry at grazing angles), with a floor on the roughness so the renderer adds its glint too.

#include "res://shaders/surf.gdshaderinc"
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/beach_golden.gdshaderinc"

global uniform vec3 origin_shift;
global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float ground_detail;
// Rain darkens the sand the way it darkens the streets (PropFactory.set_wetness()).
global uniform float road_wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// PropFactory.pbr("sand", 2.0, Color(1.0, 0.95, 0.85)): the same tint and tile.
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float tile_m = 2.0;
uniform float normal_scale = 0.8;
// How far seaward of the mapped waterline the swash starts: the flat water plane (y 0.15) meets
// the sand about two metres out, and the sheet has to start under that seam to hide it.
uniform float swash_origin = 2.5;
// Wet sand: how much darker, and how glossy (roughness), than dry.
uniform float wet_darken = 0.42;
uniform float wet_roughness = 0.30;
// The sheet of water: how much it darkens the sand under it, its own tint (LINEAR), and how
// strongly it mirrors the sky.
uniform float sheet_darken = 0.24;
uniform vec3 sheet_tint = vec3(0.90, 0.97, 0.98);
// Caustics on the sand under the sheet (surf_caustic(); the ocean's shallows use the same net).
uniform float caustic_gain = 0.8;
// The wet sand's mean colour under the sheet (LINEAR, handed over in the renderer's own space; the
// sea's floor_color), which the caustics add.
uniform vec3 caustic_tone = vec3(0.085, 0.068, 0.042);
uniform float sheet_mirror = 1.0;
uniform vec3 lace_color = vec3(0.82, 0.85, 0.86);
// Past this distance (metres) the swash is not worked out at all.
uniform float swash_distance = 320.0;
// The damp band above the swash (beach_golden): how much darker, how glossy, how strongly it and
// the standing pools in it mirror the sky, and how much of the sun's glow it takes at golden hour.
uniform float band_darken = 0.18;
uniform float band_roughness = 0.32;
uniform float band_mirror = 0.16;
uniform float pool_mirror = 0.95;
uniform float sun_glow = 0.6;

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 tw = wpos.xz + origin_shift.xz;
	vec2 uv = tw / tile_m;
	vec3 alb = texture(albedo_tex, uv).rgb * tint * COLOR.rgb;
	float rough = texture(rough_tex, uv).r;
	vec3 nm = texture(normal_tex, uv).rgb;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float dist = length(wpos - eye);
	vec3 view_dir = normalize(wpos - eye);

	float up = UV2.x + swash_origin;
	float sheet = 0.0;
	float front = 0.0;
	float wet = 0.0;
	float rush = 0.0;
	float reach_max = surf_extra.x * (SURF_H_LO + SURF_H_SPAN) * (SURF_H_LO + SURF_H_SPAN) + 2.0;
	if (dist < swash_distance && up < reach_max) {
		// The waterline point of this row: straight seaward along -x.
		vec2 shore_p = tw - vec2(UV2.x, 0.0);
		sheet = surf_swash(shore_p, up, TIME, front, wet, rush);
	}
	// Rain wets it all.
	float damp = max(wet * 0.9, road_wetness * 0.75);
	alb *= 1.0 - wet_darken * damp;
	rough = mix(rough, wet_roughness, damp);

	// The postcard pass (beach_golden.gdshaderinc; golden_on 0 skips all of it): the damp band the
	// last tide left above the swash, wind ripples and hummocks on the dry sand, footprints, the
	// wrack line, quartz glints. Slopes are true-world (dh/dx, dh/dz), turned into the normal map
	// through the mesh's own tangent frame so no texture convention can flip them.
	float band = 0.0;
	float pool = 0.0;
	float glint = 0.0;
	// Metres per pixel, taken outside any branch (derivatives in divergent flow are undefined:
	// llvmpipe hands back 0 and the ripples aliased to a corduroy at every range).
	float px = length(fwidth(tw));
	if (golden_on > 0.5 && dist < 260.0) {
		float tide = reach_max + 5.0 + 3.0 * (bg_noise(vec2(tw.y * 0.05, 1.0)) - 0.5);
		band = (1.0 - smoothstep(tide - 4.0, tide + 2.0, up)) * (1.0 - wet * 0.5);
		// Shallow water left standing in the low-tide terrace's troughs: mirror patches.
		pool = band * smoothstep(0.58, 0.72, bg_noise(tw * vec2(0.09, 0.05) + 2.0)) * (1.0 - smoothstep(reach_max * 0.6, reach_max + 3.0, up));
		alb *= 1.0 - band * band_darken;
		rough = mix(rough, band_roughness, band);
		float dry = smoothstep(tide + 2.0, tide + 12.0, up) * (1.0 - damp) * (1.0 - road_wetness);
		float keep = smoothstep(reach_max * 0.55, reach_max + 1.5, up);
		float prwet = 1.0 - smoothstep(tide, tide + 8.0, up);
		float trod;
		vec3 g = bg_ripples(tw, px, dry) + bg_hummocks(tw, px, dry) * mix(1.0, 0.4, band) + bg_footprints(tw, px, prwet, keep, trod);
		alb *= 1.0 - 0.07 * trod;
		// Wet prints hold a film of water; dry ones show the darker damp sand they turned up.
		float dent = clamp(-g.z / max(print_depth, 1e-4), 0.0, 1.0);
		alb *= 1.0 - dent * mix(0.05, 0.16, prwet);
		rough = mix(rough, 0.18, dent * prwet * 0.7);
		float wr = bg_wrack(tw, up, reach_max, px);
		alb = mix(alb, cs_as_uniform(mix(vec3(0.20, 0.17, 0.10), vec3(0.11, 0.10, 0.06), bg_noise(tw * 3.0))), wr);
		rough = mix(rough, 0.6, wr);
		vec3 dv = (VIEW_MATRIX * vec4(-g.x, 0.0, -g.y, 0.0)).xyz;
		nm.xy += 0.5 * vec2(dot(dv, TANGENT), dot(dv, BINORMAL)) / max(normal_scale, 0.05);
		glint = bg_glint(tw, view_dir, normalize(sun_direction), px, dry * (1.0 - wr));
		rough = mix(rough, 0.04, pool);
		nm = mix(nm, vec3(0.5, 0.5, 1.0), pool * 0.8);
	}

	// The sheet: sand seen through a few centimetres of water, darker and a touch cooler, with
	// the texture's relief drowned and a fine ripple of its own running with the flow.
	float sh = smoothstep(0.0, 0.10, sheet);
	bool wrv = water_review > 0.5;
	// (WATER_REVIEW=0: the old sheet, half as dark again and bluer.)
	vec3 s_tint = wrv ? sheet_tint * (1.0 - sheet_darken) : vec3(0.80, 0.93, 0.95) * 0.50;
	alb *= mix(vec3(1.0), s_tint, sh);
	// The sun's caustics on the sand under it (surf_caustic(), the shallows' own net): the brightest
	// tell that the sheet is clear water and not a grey film (water-review).
	if (wrv && sh > 0.001 && ground_detail > 0.5 && dist < swash_distance * 0.4) {
		vec3 sn = normalize(sun_direction);
		float sun_in = smoothstep(-0.02, 0.2, sn.y) * (1.0 - night_factor) * (1.0 - road_wetness);
		if (sun_in > 0.001) {
			float c = surf_caustic(tw, 0.04 + 0.12 * sheet, px, TIME);
			// Added at the wet sand's mean colour, not multiplied into the texture: multiplied, every
			// bright grain of the sand under a line became a sparkle, in rows down the beach.
			alb += cs_as_uniform(caustic_tone) * caustic_gain * sun_in * sh * c * (1.0 - smoothstep(swash_distance * 0.25, swash_distance * 0.4, dist));
		}
	}
	rough = mix(rough, 0.06, sh);
	nm = mix(nm, vec3(0.5, 0.5, 1.0), sh * 0.85);
	float lace = 0.0;
	if (sh > 0.001 || front > 0.001) {
		bool rich = ground_detail > 0.5;
		vec2 flow = vec2(-rush * TIME * 1.6, 0.0);
		float rip = surf_noise(tw * vec2(1.6, 0.7) + flow + vec2(0.0, TIME * 0.3));
		nm.xy += (vec2(rip, surf_noise(tw * vec2(0.7, 1.6) - flow + 5.0)) - 0.5) * 0.18 * sh;
		float fizz;
		float edge;
		if (wrv) {
			// Foam (water-review): the moving edge carries a ragged band of churned foam that breaks into
			// islands and threads behind it (surf_foam(), the ocean's own foam, stretched along the
			// shore), a fine fizz through the uprush. Under a pixel both are drawn as their average. It
			// was a web of noise contours, which read as white spaghetti on the sheet.
			vec2 wp = vec2(tw.x / 0.42, tw.y / 0.62) + vec2(rush * TIME * 0.45, 0.0);
			float fpx = px / 0.42;
			// Fresh only along the very edge: a hand's breadth behind it the foam is already breaking up.
			float age = clamp((1.0 - front) * 2.2, 0.0, 1.0);
			float fm = surf_foam(wp, mix(0.10, 0.92, age), fpx);
			fizz = rich ? smoothstep(0.86, 0.95, surf_noise(tw * 16.0 + vec2(TIME * 0.5, 0.0))) : 0.0;
			fizz *= smoothstep(0.3, 0.7, surf_noise(tw * 1.1 + 4.0));
			// Its cells are 6 cm: averaged once a pixel is a few centimetres (at 0.42 m it aliased into
			// rows of white specks down the beach).
			fizz = mix(fizz, 0.04, smoothstep(0.015, 0.05, px));
			// The foam line itself (the last ~30 cm of the sheet), and the churn behind it.
			float line = smoothstep(0.86, 0.95, front) * mix(0.55, 1.0, fm);
			edge = max(line, fm * pow(front, 2.0) * 0.9);
		} else {
			// Foam: a thin web of bubble lines along the moving edge (thin lines where warped noise
			// crosses its middle, never blobs), a fine fizz through the uprush. Under a pixel both
			// are drawn as their average.
			vec2 wp = tw * 2.4 + vec2(rush * TIME * 0.8, 0.0);
			// How many web cells a pixel spans (the screen derivative, so a grazing view, where a
			// pixel is long down the beach, fades as it should).
			float px = clamp((length(fwidth(wp)) - 0.25) / 0.6, 0.0, 1.0);
			vec2 warp = vec2(surf_noise(wp * 0.37 + 2.0), surf_noise(wp * 0.37 + 6.0)) - 0.5;
			float web = surf_noise(wp + warp * 2.2);
			float lw = mix(0.05, 0.16, px);
			float lines = 1.0 - smoothstep(lw * 0.4, lw, abs(web - 0.5));
			lines = mix(lines, 0.3, px * px);
			fizz = rich ? smoothstep(0.86, 0.95, surf_noise(tw * 16.0 + vec2(TIME * 0.5, 0.0))) : 0.0;
			fizz *= smoothstep(0.3, 0.7, surf_noise(tw * 1.1 + 4.0));
			fizz = mix(fizz, 0.04, clamp(px * 2.0, 0.0, 1.0));
			// The foam line itself (the last ~30 cm of the sheet), and the web behind it.
			float line = smoothstep(0.86, 0.95, front) * mix(0.75, 1.0, surf_noise(tw * vec2(0.8, 3.0)));
			edge = max(line, lines * pow(front, 1.5) * 0.85);
		}
		float bubbles = sh * max(rush, 0.0) * fizz * (wrv ? 0.16 : 0.35);
		lace = clamp(max(edge, bubbles), 0.0, 1.0);
		lace *= 1.0 - smoothstep(swash_distance * 0.5, swash_distance, dist);
	}
	alb = mix(alb, lace_color, lace);
	rough = mix(rough, 0.55, lace);

	// The sky in the sheet (and a little in wet sand), emitted by fresnel like the sea's.
	vec3 n_w = normalize(vec3(0.0, 1.0, 0.0) + vec3(nm.x - 0.5, 0.0, nm.y - 0.5) * 0.15);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n_w, -view_dir), 0.0, 1.0), 5.0);
	vec3 refl = reflect(view_dir, n_w);
	vec3 sky = golden_on > 0.5 ? cs_as_uniform(sky_tint.rgb) : sky_tint.rgb;
	vec3 sky_ref = mix(sky, sky * vec3(0.55, 0.72, 1.0), smoothstep(0.0, 0.55, refl.y));
	float mirror = (sh * sheet_mirror + damp * 0.25) * (1.0 - lace);
	vec3 sun_n = normalize(sun_direction);
	float sun_glint = pow(max(dot(refl, sun_n), 0.0), 400.0) * 4.0 * (1.0 - night_factor) * step(0.0, sun_n.y);
	vec3 sun_col = vec3(1.0, 0.92, 0.8);
	if (golden_on > 0.5) {
		// The low sun's colour, and the glow of the sky round it mirrored in the wet sand: the
		// sunset path the sea throws up the beach.
		float gold = (1.0 - smoothstep(0.05, 0.4, sun_n.y)) * smoothstep(-0.08, 0.0, sun_n.y);
		sun_col = cs_as_uniform(mix(vec3(1.0, 0.95, 0.86), vec3(1.0, 0.62, 0.30), gold));
		vec2 rh = normalize(refl.xz + vec2(1e-4, 0.0));
		vec2 sh2 = normalize(sun_n.xz + vec2(1e-4, 0.0));
		float toward = pow(max(dot(rh, sh2), 0.0), 6.0) * (1.0 - smoothstep(0.0, 0.35, refl.y));
		sky_ref += sun_col * toward * gold * sun_glow;
		float wet_mirror = band * band_mirror + pool * pool_mirror;
		mirror = max(mirror, wet_mirror * (1.0 - lace));
		// A broad sun path in damp sand (rougher than the sheet) on top of the sheet's sharp glint.
		sun_glint += pow(max(dot(refl, sun_n), 0.0), mix(40.0, 600.0, pool)) * mix(0.8, 3.0, pool) * band * (1.0 - night_factor) * step(0.0, sun_n.y);
		EMISSION = (sky_ref * fres + sun_col * sun_glint * fres) * mirror + sun_col * glint * (1.0 - night_factor);
	} else {
		EMISSION = (sky_ref * fres + sun_col * sun_glint * fres) * mirror;
	}
	ALBEDO = alb * (1.0 - fres * (sh * 0.8 + pool * 0.6));
	ROUGHNESS = rough;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_scale;
	SPECULAR = 0.5;
}
