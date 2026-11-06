shader_type spatial;
// Cloth on a car lot (CarDealers): pennant strings, bunting, feather flags and the brand flags
// on their poles. One material for all of them, one mesh a dealership.
//
// Mesh contract: COLOR.rgb the cloth colour (sRGB, as written; the string itself is a dark
// rope), COLOR.a 1 cloth / 0 rope. UV2.x is how free the vertex is (0 on the edge that is
// sewn to the string or the pole, 1 at the tip or the fly), UV2.y a seed per piece. NORMAL is
// the cloth's normal, which is the way it flutters. UV is 0..1 across the piece (u from the
// sewn edge, v along it) for the hem and the print.
#include "res://shaders/color_space.gdshaderinc"

render_mode cull_disabled;

global uniform float wind_factor;

// Flutter amplitude at the free edge (m) in a calm and in a gale.
uniform float flutter_calm = 0.06;
uniform float flutter_gale = 0.32;
uniform float flutter_speed = 7.5;

varying float v_cloth;
varying float v_free;

void vertex() {
	float w = UV2.x;
	float seed = UV2.y;
	float wind = clamp(wind_factor, 0.0, 2.0);
	float amp = mix(flutter_calm, flutter_gale, clamp(wind * 0.6, 0.0, 1.0)) * w * w;
	float t = TIME * flutter_speed * (0.85 + 0.3 * fract(seed * 7.13));
	// Waves running from the sewn edge to the free one, plus a slower billow.
	float wave = sin(t - w * 5.0 + seed * 31.0) + 0.5 * sin(1.7 * t - w * 9.0 + seed * 11.0);
	float billow = sin(0.9 * TIME + seed * 5.0) * 0.6;
	VERTEX += NORMAL * amp * (wave + billow) * COLOR.a;
	// The free edge streams back a little downwind (local -NORMAL is as good as any side).
	v_cloth = COLOR.a;
	v_free = w;
}

void fragment() {
	vec3 col = cs_srgb_to_linear(COLOR.rgb);
	if (v_cloth > 0.5) {
		// Woven polyester: a faint weave, a hem along the free edge, shading in the folds the
		// wave makes (the normal does most of it).
		vec2 g = abs(fract(UV * vec2(120.0, 120.0)) - 0.5);
		col *= 0.95 + 0.05 * step(0.3, max(g.x, g.y));
		col *= 1.0 - 0.12 * smoothstep(0.93, 0.97, UV.x);
		ROUGHNESS = 0.62;
		SPECULAR = 0.3;
		// Sun through thin cloth.
		BACKLIGHT = cs_out(col * 0.45);
	} else {
		ROUGHNESS = 0.8;
		SPECULAR = 0.2;
	}
	ALBEDO = cs_out(col);
}
