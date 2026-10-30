shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// The street-level hardware FacadeStreet hangs on a Building's lowest storeys (downpipes, conduit,
// meter and panel boxes, wall condensers, window grilles, door lamps and steps, gooseneck sign
// lamps, shutter housings, thresholds): one mesh a building, one draw. What a face is rides in the
// vertex alpha (kind / 16, FacadeStreet.K_*), its paint in COLOR.rgb as written (sRGB, decoded
// here: vertex colours arrive raw on both renderers), UV in metres along the piece, UV2.x 1 on a
// lamp lens that is lit after dark. Linear on both renderers (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

varying flat float kind;
varying vec3 wpos;

float fsp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fsp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fsp_hash(i), fsp_hash(i + vec2(1.0, 0.0)), f.x),
		mix(fsp_hash(i + vec2(0.0, 1.0)), fsp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	kind = floor(COLOR.a * 16.0 + 0.5);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = cs_srgb_to_linear(COLOR.rgb);
	float rough = 0.55;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	float px = length(fwidth(wpos));
	float mott = fsp_noise(UV * vec2(6.0, 3.0));
	if (kind < 0.5) {
		// Paint on metal: a little chalky, chipped on the edges of what gets knocked.
		c *= 0.9 + 0.2 * mott;
		rough = 0.5 + 0.15 * mott;
		metal = 0.1;
	} else if (kind < 1.5) {
		// Galvanised steel: spangled grey, dulled.
		c = vec3(0.40, 0.41, 0.40) * (0.82 + 0.3 * fsp_noise(UV * 22.0));
		rough = 0.48;
		metal = 0.7;
	} else if (kind < 2.5) {
		// Concrete: a step or a plinth, scuffed paler on its nosing.
		c *= 0.86 + 0.24 * fsp_noise(UV * 9.0);
		rough = 0.92;
	} else if (kind < 3.5) {
		// A lamp's lens: frosted, lit after dark when UV2.x says so.
		c = vec3(0.75, 0.74, 0.70);
		rough = 0.25;
		em = cs_srgb_to_linear(COLOR.rgb) * 6.0 * UV2.x * clamp(lamp_factor, 0.0, 1.0);
	} else if (kind < 4.5) {
		// A condenser's fan grille: concentric wire rings over the dark fan, the hub in the middle.
		vec2 q = UV - 0.5;
		float r = length(q);
		float ring = 1.0 - smoothstep(0.0, max(px * 2.0, 0.01), abs(fract(r / 0.03) - 0.5) * 0.03);
		ring = mix(ring, 0.35, smoothstep(0.004, 0.012, px));
		float spoke = 1.0 - smoothstep(0.0, 0.02, abs(sin(atan(q.y, q.x) * 2.0)) * r);
		float hub = 1.0 - smoothstep(0.06, 0.07, r);
		c = mix(vec3(0.03), cs_srgb_to_linear(COLOR.rgb) * 0.8, clamp(ring + spoke * 0.6 + hub, 0.0, 1.0));
		c *= step(r, 0.5);
		rough = 0.6;
		metal = 0.3;
	} else if (kind < 5.5) {
		// A meter's glass: dark, glossy.
		c = vec3(0.04, 0.045, 0.05);
		rough = 0.06;
		metal = 0.0;
	} else if (kind < 6.5) {
		// Copper line set, gone brown.
		c = vec3(0.42, 0.20, 0.10) * (0.8 + 0.3 * mott);
		rough = 0.4;
		metal = 0.85;
	} else if (kind < 7.5) {
		// Rubber, insulation, the black of a cable.
		c = vec3(0.025);
		rough = 0.75;
	} else if (kind < 8.5) {
		// Wrought iron: paint over rust, the rust showing where hands and rain go.
		float rust = smoothstep(0.62, 0.85, fsp_noise(UV * vec2(9.0, 4.0)));
		c = mix(c, vec3(0.19, 0.08, 0.035), rust * 0.6);
		rough = 0.55 + 0.3 * rust;
		metal = 0.3;
	} else {
		// Stone or terrazzo: a threshold, worn glossy in the middle.
		float chips = step(0.86, fsp_hash(floor(UV * 60.0)));
		c *= 0.9 + 0.15 * chips;
		rough = 0.35;
	}
	ALBEDO = cs_out(c);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
	EMISSION = cs_out(em);
}
