shader_type spatial;
render_mode cull_back;

// A light rail section seen from far off (LightRailSystem's far trains, one MultiMesh box per
// section): a 1 m cube scaled to the section, white over a coral band, a dark window band whose
// windows glow after dark - from the air at night the line reads as strings of lit boxes. The
// box's local y is 0..1 (rail to roof), x and z -0.5..0.5.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;

uniform vec3 body_color = vec3(0.62, 0.63, 0.62);
uniform vec3 band_color = vec3(0.80, 0.135, 0.075);
uniform vec3 window_color = vec3(0.012, 0.012, 0.014);
uniform vec3 roof_color = vec3(0.30, 0.31, 0.32);
uniform vec3 lit_color = vec3(1.0, 0.86, 0.62);
uniform float lit_energy = 2.4;

varying vec3 lp;
varying vec3 ln;


void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}


void fragment() {
	float y = lp.y;
	vec3 alb = body_color;
	vec3 emit = vec3(0.0);
	if (ln.y > 0.5) {
		alb = roof_color;
	} else if (y < 0.2) {
		alb = window_color;
	} else if (y > 0.31 && y < 0.38) {
		alb = band_color;
	} else if (y > 0.38 && y < 0.74) {
		alb = window_color;
		// Lit windows on the sides at night (pillars every ~1 m of the section).
		float pillar = step(0.86, fract(lp.z * 13.5 / 1.05));
		emit = lit_color * lit_energy * clamp(night_factor, 0.0, 1.0) * (1.0 - pillar) * step(0.5, abs(ln.x));
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = 0.4;
	EMISSION = cs_out(emit);
}
