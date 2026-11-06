
// A car's number plates and badges (CarDetail): real raised geometry, the kind of surface in
// the vertex alpha (x 8: 0 plate sheeting, 1 embossed ink, 2 chrome, 3 black plastic, 4 the
// registration tag, 5 the banner's red, 6 the tag line's blue), its colour in the vertex rgb as
// a display (sRGB) number, UV.x 1 on the rear plate (lit by its lamp after dark on the `lit`
// copy of this material). Shared by every car: two materials in the whole city.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

uniform float plate_lamp = 0.0;
// Chrome on a renderer that can light a metal (Forward+); Compatibility gets a satin grey, like
// Vehicle._part_material()'s chrome.
uniform bool chrome_metal = true;

varying vec3 lp;

#ifdef CRASH_DETAIL
// A crashed car's copy (CrashDeform): the plates and badges ride the crushed body. The mesh is
// in the car's own space; the crumples are in the body model's, so the two transforms between.
#include "res://shaders/car_damage.gdshaderinc"
#include "res://shaders/car_crumple.gdshaderinc"
uniform mat4 to_mesh = mat4(1.0);
uniform mat4 from_mesh = mat4(1.0);
#endif


void vertex() {
	lp = VERTEX;
#ifdef CRASH_DETAIL
	if (cr_any()) {
		vec3 p = (to_mesh * vec4(VERTEX, 1.0)).xyz;
		vec3 n = normalize(mat3(to_mesh) * NORMAL);
		cr_apply(p, n);
		VERTEX = (from_mesh * vec4(p, 1.0)).xyz;
		NORMAL = normalize(mat3(from_mesh) * n);
	}
#endif
}


float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


void fragment() {
	int kind = int(COLOR.a * 8.0);
	vec3 col = cs_srgb_to_linear(COLOR.rgb);
	float rough = 0.45;
	float metal = 0.0;
	float spec = 0.5;
	// A plate's road film: grit toward the bottom edge and a little everywhere, in metres.
	float grit = h13(floor(lp * 900.0)) * 0.5 + h13(floor(lp * 140.0)) * 0.5;
	if (kind == 0) {
		// Retroreflective sheeting: a fine bead texture, slightly glossy.
		col *= 0.93 + 0.07 * grit;
		rough = 0.32;
	} else if (kind == 1 || kind == 5 || kind == 6) {
		rough = 0.38;
	} else if (kind == 2) {
		if (chrome_metal) {
			col = vec3(0.86, 0.87, 0.89);
			metal = 1.0;
			rough = 0.09;
		} else {
			col = cs_srgb_to_linear(vec3(0.70, 0.71, 0.73));
			rough = 0.28;
		}
	} else if (kind == 3) {
		rough = 0.62;
		spec = 0.35;
	} else if (kind == 4) {
		rough = 0.30;
	}
	// Road dust settles on the plates (not the chrome, which is wiped when the car is).
	if (kind != 2) {
		col = mix(col, vec3(0.18, 0.16, 0.13), 0.10 * grit * (1.0 - road_wetness));
	}
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(rough, rough * 0.5, road_wetness);
	METALLIC = metal;
	SPECULAR = spec;
	// The rear plate's lamp: two small LEDs over it light the sheeting white after dark.
	if (UV.x > 0.5 && kind != 2 && kind != 3) {
		EMISSION = cs_out(col * 0.55 * plate_lamp * lamp_factor);
	}
}
