shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

// A round's streak (GunplayFeel.tracer). The old tracer was a lit cylinder from the muzzle to the
// hit, drawn whole on the first frame and shrunk away: a laser line, the clearest tell that the
// gun is a game's. A round is never seen as a line - the eye catches a short hot streak racing
// out (motion smear of the bullet), and behind it, faintly, the air it went through.
//
// One quad from the muzzle (UV.x 0) to the end (UV.x 1), its two long edges UV.y -1 and +1, the
// bore direction in NORMAL. The vertex stage turns it to face the camera about its own axis (a
// ribbon: from any angle it is the same width) and never lets it go under `min_px` pixels, so a
// round down the street a hundred metres away is still a thread of light. The fragment draws the
// streak where the round is now (`head`, metres from the muzzle) and a fading trail behind it.
// Colours linear, handed over with cs_out(); the profile reaches zero at the quad's edge.

#include "res://shaders/color_space.gdshaderinc"

// Length of the quad, metres.
uniform float length_m = 10.0;
// Where the round is, metres from the muzzle (past length_m once it has landed).
uniform float head = 0.0;
// How long the bright streak is behind the round, metres.
uniform float tail = 7.0;
// Width of the streak's core, metres, and the least it is ever drawn (pixels).
uniform float width_m = 0.022;
uniform float min_px = 1.6;
// The trail behind the streak (0 gone): the faint hot air the round left.
uniform float trail = 0.0;
uniform float heat = 5.0;
uniform vec3 core_color = vec3(1.0, 0.72, 0.36);
uniform vec3 glow_color = vec3(1.0, 0.42, 0.12);
// The viewport's height in pixels (GunplayFeel sets it: VIEWPORT_SIZE is not to be trusted in a
// vertex stage, CLAUDE.md's far-buildings note).
uniform float viewport_px = 1080.0;

varying float v_px_scale;


void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 side = cross(axis, normalize(p));
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : vec3(1.0, 0.0, 0.0);
	// Metres a pixel covers at this depth (abs: PROJECTION[1][1] is negative on Compatibility).
	float px = max(-p.z, 0.05) * 2.0 / max(abs(PROJECTION_MATRIX[1][1]) * viewport_px, 1.0);
	float w = max(width_m * 2.5, px * min_px * 2.5);
	// How much the drawn width outgrew the real one: a thread under a pixel is spread thinner.
	v_px_scale = clamp(width_m * 2.5 / w, 0.08, 1.0);
	VERTEX = p + side * UV.y * w;
	NORMAL = -normalize(p);
}


void fragment() {
	float s = UV.x * length_m;
	float across = abs(UV.y);
	// A hot core and a soft sleeve, both to zero at the edge.
	float core = (1.0 - smoothstep(0.0, 0.35, across));
	float sleeve = pow(1.0 - across, 2.2);
	// The streak: brightest at the round, fading back over `tail`; nothing ahead of it.
	float d = head - s;
	float streak = step(0.0, d) * (1.0 - smoothstep(0.0, max(tail, 0.01), d));
	streak = pow(streak, 1.4);
	// The trail: everything the round has passed, faint.
	float passed = step(0.0, d);
	float air = passed * trail * 0.12;
	vec3 col = core_color * core * streak * 1.3 + glow_color * sleeve * (streak * 0.45 + air);
	col *= v_px_scale * heat;
	// Never right at the muzzle (the flash is there).
	col *= smoothstep(0.15, 0.9, s);
	ALBEDO = cs_out(col);
}
