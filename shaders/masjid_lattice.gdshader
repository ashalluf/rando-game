shader_type spatial;
render_mode cull_disabled;

// The green mashrabiya screens in the tall window bays of Masjid Omar ibn Al-Khattab: a close
// diamond lattice of painted metal bars, cut out with alpha scissor so the room and the sky
// show through the gaps and nothing has to be sorted. UV is metres on the screen's own plane.
// Seen from inside against daylight it is dark bars on bright sky, which is the look of the
// prayer hall's windows; seen from the street it is a dark green texture over a darker room.

uniform vec3 bar_color : source_color = vec3(0.07, 0.22, 0.16);
// Size of one diamond cell (point to point), in metres, and the bar width as a share of it.
uniform float cell = 0.16;
uniform float bar = 0.22;
// A slightly heavier square frame every `frame_every` cells, as the panels are welded up.
uniform float frame_every = 8.0;

void fragment() {
	vec2 p = UV / cell;
	// Diamonds: two sets of bars at +-45 degrees.
	vec2 d = vec2(p.x + p.y, p.x - p.y);
	vec2 f = abs(fract(d) - 0.5);
	float on_diag = step(0.5 - bar * 0.5, max(f.x, f.y));
	// The panel frame, square to the window.
	vec2 g = abs(fract(p / frame_every) - 0.5) * frame_every;
	float on_frame = step(frame_every * 0.5 - bar * 0.9, max(g.x, g.y));
	float solid = max(on_diag, on_frame);
	if (solid < 0.5) {
		discard;
	}
	ALBEDO = bar_color;
	METALLIC = 0.35;
	ROUGHNESS = 0.42;
}
