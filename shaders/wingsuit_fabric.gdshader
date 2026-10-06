shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// The wingsuit's fabric (scripts/player/wingsuit_fx.gd): ripstop nylon in panels. UV is metres
// (along the edge the membrane hangs from, across it), UV2 (u, v) 0..1 with 2 added to v on the
// tail wing. Chordwise seams every `panel` metres with a row of stitches, the cloth billowing
// between them (a normal tilt) and darker in the valleys; a signal-orange band on every trailing
// edge and down the sleeve; the inlets near the shoulder; a flutter that grows with the airspeed
// (`flutter`, set per frame), strongest at the trailing edge. Colours are linear
// (color_space.gdshaderinc), the same on both renderers.
#include "res://shaders/color_space.gdshaderinc"

uniform float flutter = 0.0;
uniform float panel = 0.26;
uniform vec3 cloth_color = vec3(0.018, 0.019, 0.022);
uniform vec3 seam_color = vec3(0.008, 0.008, 0.009);
uniform vec3 accent_color = vec3(0.78, 0.16, 0.025);
uniform float accent_width = 0.09;
uniform float roughness_cloth = 0.42;

varying float v_edge;
varying float v_tail;

void vertex() {
	float v = UV2.y;
	v_tail = step(1.5, v);
	v = v - 2.0 * v_tail;
	v_edge = v;
	// A ripple running back along the trailing edge, faster and bigger with the airspeed.
	float w = sin(TIME * (19.0 + 9.0 * flutter) - UV.x * 7.0 + v * 5.0) + 0.5 * sin(TIME * 31.0 - UV.x * 13.0);
	VERTEX += NORMAL * w * flutter * 0.022 * v * v;
}

void fragment() {
	vec2 m = UV;
	float px = max(fwidth(m.x), fwidth(m.y));
	// Panels: seams across the chord every `panel` metres along the edge.
	float cell = m.x / panel;
	float f = fract(cell);
	float seam_d = min(f, 1.0 - f) * panel;
	float seam = 1.0 - smoothstep(0.004, 0.004 + px * 1.5, seam_d);
	// Stitch rows either side of a seam, faded to their average under a pixel.
	float stitch_row = 1.0 - smoothstep(0.0015, 0.0015 + px, abs(seam_d - 0.011));
	float stitch = stitch_row * mix(step(0.5, fract(m.y / 0.008)), 0.5, smoothstep(0.002, 0.008, px));
	// The billow between seams: the cloth bulges in the middle of a panel.
	float bulge = sin(f * 3.14159);
	float slope = cos(f * 3.14159) * 0.55 * (1.0 - smoothstep(0.02, 0.08, px));
	NORMAL_MAP = normalize(vec3(0.5 - slope * 0.5, 0.5, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	// Ripstop: a faint grid, averaged away with distance.
	vec2 rg = abs(fract(m / 0.007) - 0.5);
	float rip = (1.0 - smoothstep(0.38, 0.5, max(rg.x, rg.y))) * (1.0 - smoothstep(0.001, 0.004, px));
	// Accent: the trailing edge band (v near 1) and, on the arm wings, the sleeve's edge.
	float trail_band = smoothstep(1.0 - accent_width * 1.6, 1.0 - accent_width * 1.3, v_edge);
	float sleeve = (1.0 - v_tail) * (1.0 - smoothstep(0.035, 0.05, v_edge));
	float accent = max(trail_band, sleeve);
	// Air inlets near the shoulder: dark mesh slots in the arm wing's first panel.
	float inlet = (1.0 - v_tail) * step(UV2.x, 0.12) * smoothstep(0.12, 0.14, v_edge) * (1.0 - smoothstep(0.4, 0.42, v_edge));
	vec3 col = mix(cloth_color, accent_color, accent);
	col *= mix(0.82, 1.06, bulge);
	col = mix(col, seam_color, seam * 0.8);
	col = mix(col, col * 1.8 + 0.02, stitch * 0.35);
	col *= 1.0 + rip * 0.12;
	col = mix(col, vec3(0.004), inlet * 0.85);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(roughness_cloth, 0.75, seam + inlet);
	SPECULAR = 0.45;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// The cloth lets a little light through, red-orange where the accent is.
	BACKLIGHT = cs_out(mix(vec3(0.02), accent_color * 0.35, accent));
}
