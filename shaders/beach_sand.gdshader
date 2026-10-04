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
uniform float sheet_darken = 0.50;
uniform vec3 sheet_tint = vec3(0.80, 0.93, 0.95);
uniform float sheet_mirror = 1.0;
uniform vec3 lace_color = vec3(0.82, 0.85, 0.86);
// Past this distance (metres) the swash is not worked out at all.
uniform float swash_distance = 320.0;

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

	// The sheet: sand seen through a few centimetres of water, darker and a touch cooler, with
	// the texture's relief drowned and a fine ripple of its own running with the flow.
	float sh = smoothstep(0.0, 0.10, sheet);
	alb *= mix(vec3(1.0), sheet_tint * (1.0 - sheet_darken), sh);
	rough = mix(rough, 0.06, sh);
	nm = mix(nm, vec3(0.5, 0.5, 1.0), sh * 0.85);
	float lace = 0.0;
	if (sh > 0.001 || front > 0.001) {
		bool rich = ground_detail > 0.5;
		vec2 flow = vec2(-rush * TIME * 1.6, 0.0);
		float rip = surf_noise(tw * vec2(1.6, 0.7) + flow + vec2(0.0, TIME * 0.3));
		nm.xy += (vec2(rip, surf_noise(tw * vec2(0.7, 1.6) - flow + 5.0)) - 0.5) * 0.18 * sh;
		// Foam: a thin web of bubble lines along the moving edge (thin lines where warped noise
		// crosses its middle, never blobs), a fine fizz through the uprush. Under a pixel both
		// are drawn as their average.
		float px = clamp(dist / 60.0, 0.0, 1.0);
		vec2 wp = tw * 2.4 + vec2(rush * TIME * 0.8, 0.0);
		vec2 warp = vec2(surf_noise(wp * 0.37 + 2.0), surf_noise(wp * 0.37 + 6.0)) - 0.5;
		float web = surf_noise(wp + warp * 2.2);
		float lw = mix(0.05, 0.16, px);
		float lines = 1.0 - smoothstep(lw * 0.4, lw, abs(web - 0.5));
		lines = mix(lines, 0.3, px * px);
		float fizz = rich ? smoothstep(0.80, 0.92, surf_noise(tw * 9.0 + vec2(TIME * 0.5, 0.0))) : 0.0;
		fizz = mix(fizz, 0.08, px);
		float band = front * front;
		float edge = band * max(lines, smoothstep(0.85, 1.0, front) * 0.55);
		float bubbles = sh * max(rush, 0.0) * fizz * 0.5;
		lace = clamp(max(edge, bubbles), 0.0, 1.0);
		lace *= 1.0 - smoothstep(swash_distance * 0.5, swash_distance, dist);
	}
	alb = mix(alb, lace_color, lace);
	rough = mix(rough, 0.55, lace);

	// The sky in the sheet (and a little in wet sand), emitted by fresnel like the sea's.
	vec3 n_w = normalize(vec3(0.0, 1.0, 0.0) + vec3(nm.x - 0.5, 0.0, nm.y - 0.5) * 0.15);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n_w, -view_dir), 0.0, 1.0), 5.0);
	vec3 refl = reflect(view_dir, n_w);
	vec3 sky_ref = mix(sky_tint.rgb, sky_tint.rgb * vec3(0.55, 0.72, 1.0), smoothstep(0.0, 0.55, refl.y));
	float mirror = (sh * sheet_mirror + damp * 0.25) * (1.0 - lace);
	vec3 sun_n = normalize(sun_direction);
	float glint = pow(max(dot(refl, sun_n), 0.0), 400.0) * 4.0 * (1.0 - night_factor) * step(0.0, sun_n.y);
	EMISSION = (sky_ref * fres + vec3(1.0, 0.92, 0.8) * glint * fres) * mirror;
	ALBEDO = alb * (1.0 - fres * sh * 0.8);
	ROUGHNESS = rough;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_scale;
	SPECULAR = 0.5;
}
