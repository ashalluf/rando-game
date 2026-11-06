shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/color_space.gdshaderinc"

// The warning lenses of a fire engine or an ambulance (EmergencyCar): the body model's
// `beacon_red` and `beacon_white` slots, one material per slot and per unit. Which lens flashes
// when is worked out from where the lens is on the body (the mesh's own space, MODEL_MATRIX not
// needed): the left and right banks alternate (a wig-wag), the front and the back of the body are
// a quarter cycle apart, and every lens strobes twice in its half - the pattern US apparatus run,
// so a unit reads as one coordinated light show and not as random blinking. Lit lenses are HDR so
// the glow blooms them; unlit ones keep their coloured plastic.

// The lens colour, LINEAR (a Vector3 from script, so neither renderer decodes it).
uniform vec3 lens_color = vec3(1.0, 0.04, 0.02);
// Flash cycles per second and this unit's place in the cycle.
uniform float rate = 1.35;
uniform float phase = 0.0;
// Lit and unlit brightness (multiples of the colour), and 0 switches the lights off.
uniform float energy = 6.0;
uniform float idle = 0.32;
uniform float lights_on = 1.0;
// The body's long axis in mesh space (which mesh axis runs nose to tail) and where its middle is:
// the front and back halves flash a quarter cycle apart.
uniform vec3 along_axis = vec3(0.0, 0.0, 1.0);
uniform float along_mid = 0.0;
// Which mesh axis is across the body (the wig-wag's left and right).
uniform vec3 across_axis = vec3(1.0, 0.0, 0.0);
uniform float across_mid = 0.0;
// White lenses run half as long a flash (scene lights and takedowns read as a white strobe).
uniform float duty = 0.11;

varying vec3 mesh_pos;

void vertex() {
	mesh_pos = VERTEX;
}

float strobe(float t, float start, float d) {
	float a = step(start, t) * step(t, start + d);
	float b = step(start + d * 1.6, t) * step(t, start + d * 2.6);
	return max(a, b);
}

void fragment() {
	float side = step(across_mid, dot(mesh_pos, across_axis));
	float end = step(along_mid, dot(mesh_pos, along_axis));
	float t = fract(TIME * rate + phase + side * 0.5 + end * 0.25);
	float lit = strobe(t, 0.0, duty) * lights_on;
	// A lens seen edge on still catches a little of the flash.
	vec3 c = lens_color * mix(idle, energy, lit);
	ALBEDO = cs_out(c);
}
