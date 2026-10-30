shader_type spatial;
render_mode cull_back;

// Night life (scripts/world/nightlife.gd, NightLifeKit): a club's entrance canopy and its lit
// fascia frame, a bar's projecting lightbox, the brass stanchions and velvet rope of the line, the
// carpet runner, the premiere's barriers, and the searchlight carts. One material for all of it,
// so each kind of piece is one MultiMesh draw a chunk.
//
// * Vertex colour alpha says what a face is (NightLifeKit.A_*, round(a * 20)): polished metal,
//   velvet, painted canopy steel, LED strip, downlight, carpet, rubber, the instance's paint,
//   a searchlight's lens, a lightbox face, galvanised steel. The codes sit 0.05 apart so 8-bit
//   vertex colours keep them.
// * UV2 is (roughness, metallic) per part. UV is metres (StreetClutter's projection).
// * INSTANCE_CUSTOM.rgb the venue's accent (sRGB: velvet, canopy, carpet, lightbox); .a 0.5 and
//   over, the venue is open and lit after dark; the fraction under it seeds the wear. A plain
//   MeshInstance3D (a searchlight's drum) has no instance data: `solo_lit` / `solo_paint` stand in.
// * Colour space: vertex colours and instance data arrive raw on both renderers and are authored
//   sRGB; everything is worked in linear and handed over with cs_out() (color_space.gdshaderinc).

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float road_wetness;

// The LED strips and the downlights at full night, and how much shows by day.
uniform float led_night = 9.0;
uniform float led_day = 0.35;
uniform float downlight_night = 9.0;
// A lightbox face at night (its own paint glowing through the acrylic).
uniform float box_night = 3.2;
// A searchlight's lens while it burns (the beam itself is SkyBeam's).
uniform float lens_night = 14.0;
// For a mesh drawn alone (a searchlight's drum): lit, and its paint, in place of the instance's.
uniform float solo_lit = 0.0;
uniform vec3 solo_paint = vec3(0.12, 0.12, 0.13);

varying vec3 v_local;
varying float v_mode;
varying vec3 v_paint;
varying float v_seed;
varying float v_lit;

float nl_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float nl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(nl_hash(i), nl_hash(i + vec2(1.0, 0.0)), f.x),
		mix(nl_hash(i + vec2(0.0, 1.0)), nl_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_mode = COLOR.a;
	v_paint = INSTANCE_CUSTOM.rgb;
	v_lit = step(0.5, INSTANCE_CUSTOM.a);
	v_seed = fract(INSTANCE_CUSTOM.a * 2.0);
	if (solo_lit > 0.0) {
		v_paint = solo_paint;
		v_lit = 1.0;
	}
}

void fragment() {
	int code = int(round(v_mode * 20.0));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float rough = UV2.x;
	float metal = UV2.y;
	vec3 emit = vec3(0.0);
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	float px = length(fwidth(v_local));
	float fine = clamp(1.0 - px * 60.0, 0.0, 1.0);
	vec3 paint = cs_srgb_to_linear(v_paint);
	if (code == 1) {
		// Polished brass or chrome: fine brushing, fingerprints dulling the hand height.
		float brush = nl_noise(vec2(UV.x * 3.0, UV.y * 300.0));
		rough = mix(0.16, 0.3, brush * fine) + 0.12 * smoothstep(0.8, 1.1, v_local.y) * nl_noise(UV * 40.0);
		metal = 1.0;
	} else if (code == 2) {
		// Velvet rope: the accent colour, the pile catching the light along the rope's length
		// (BACKLIGHT and a rim from the low roughness edge).
		base = paint * (0.8 + 0.25 * mix(0.5, nl_noise(UV * 90.0), fine));
		rough = 0.92;
		metal = 0.0;
	} else if (code == 3) {
		// The canopy's painted steel and fabric: the accent, a faint orange peel.
		base = paint * (0.9 + 0.1 * nl_noise(UV * 24.0 + v_seed * 7.0));
		rough = 0.55;
	} else if (code == 4) {
		// LED strip: the vertex colour glowing (open venues after dark, faint by day).
		emit = base * mix(led_day, led_night, lamp) * v_lit;
		base *= 0.4;
		rough = 0.3;
	} else if (code == 5) {
		// Recessed downlight: a warm disc.
		emit = vec3(1.0, 0.8, 0.55) * downlight_night * lamp * v_lit;
		base = vec3(0.9);
		rough = 0.2;
	} else if (code == 6) {
		// Carpet runner: the accent, a cut pile tooth, the tread worn paler down the middle,
		// darker and matted when the street is wet.
		float pile = nl_noise(v_local.xz * 180.0);
		base = paint * (0.82 + 0.25 * mix(0.5, pile, fine));
		// Runners lie along local z, centred on x 0: the tread wears down the middle.
		float wear = smoothstep(0.45, 0.0, abs(v_local.x)) * (0.5 + 0.5 * nl_noise(v_local.xz * 3.0));
		base = mix(base, base * 1.15 + 0.01, wear * 0.35);
		base *= 1.0 - 0.25 * clamp(road_wetness, 0.0, 1.0);
		rough = 0.95;
		metal = 0.0;
	} else if (code == 8) {
		base = paint;
	} else if (code == 9) {
		// A searchlight's lens: dark glass by day, a blinding disc while it burns.
		emit = vec3(0.92, 0.95, 1.0) * lens_night * lamp * v_lit;
		base = vec3(0.05);
		rough = 0.05;
		metal = 0.0;
	} else if (code == 10) {
		// A lightbox face: the accent through white acrylic, lit after dark.
		// Mixed in display numbers, then decoded: mixed in linear, the white's 0.85 swamped a dark
		// accent (a deep red's linear 0.15) and the lit face was pink on Forward+.
		vec3 face = cs_srgb_to_linear(mix(vec3(0.85), v_paint, 0.75));
		emit = face * box_night * lamp * v_lit;
		base = face;
		rough = 0.3;
	} else if (code == 11) {
		// Galvanised steel (barriers, the cart's frame): spangle and dull grey.
		base *= 0.85 + 0.2 * mix(0.5, nl_noise(UV * 55.0), fine);
		rough = 0.45;
		metal = 0.8;
	}
	// Street grime on whatever stands on the pavement.
	if (code != 4 && code != 5 && code != 9 && code != 10) {
		float gh = clamp(1.0 - v_local.y / 0.25, 0.0, 1.0);
		base *= 1.0 - 0.25 * gh * (0.5 + 0.5 * nl_noise(v_local.xz * 5.0 + v_seed * 11.0));
	}
	ALBEDO = cs_out(base);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = cs_out(emit);
	if (code == 2) {
		BACKLIGHT = cs_out(base * 0.25);
	}
}
