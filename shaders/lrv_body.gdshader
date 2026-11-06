shader_type spatial;
render_mode cull_back;

// Every painted, rubber and metal part of a Coral Line car (tools/make_light_rail.py merges them
// into one `body` material so a section is a handful of draws): the colour is the vertex colour
// (LINEAR, as the generator writes it), what the part IS rides in its alpha (kind / 16, the
// generator's KINDS): 1 paint (a clear-coated white), 2 the coral band, 3 the black window band
// and skirts, 4 roof (grey, a little dusty), 5 trim (grey metal), 6 rubber, 7 bright metal
// (wheels, poles), 8 the destination display's dark glass.

#include "res://shaders/color_space.gdshaderinc"

varying vec3 lp;


void vertex() {
	lp = VERTEX;
}


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


void fragment() {
	int kind = int(round(COLOR.a * 16.0));
	vec3 alb = COLOR.rgb;
	float rough = 0.5;
	float metal = 0.0;
	float clear = 0.0;
	if (kind == 1 || kind == 2) {
		rough = 0.28;
		metal = 0.12;
		clear = 0.6;
		// A little road dirt low on the body.
		float low = 1.0 - smoothstep(0.6, 1.3, lp.y);
		alb *= 1.0 - low * 0.18;
	} else if (kind == 3) {
		rough = 0.32;
		metal = 0.1;
		clear = 0.4;
	} else if (kind == 4) {
		rough = 0.6;
		metal = 0.3;
		alb *= 0.9 + 0.12 * hash12(floor(lp.xz * 3.0));
	} else if (kind == 5) {
		rough = 0.45;
		metal = 0.4;
	} else if (kind == 6) {
		rough = 0.8;
	} else if (kind == 7) {
		rough = 0.35;
		metal = 1.0;
	} else if (kind == 8) {
		rough = 0.15;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = clear;
	CLEARCOAT_ROUGHNESS = 0.08;
}
