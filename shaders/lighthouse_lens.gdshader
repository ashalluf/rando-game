shader_type spatial;
render_mode cull_back;

// The Fresnel lens in a lighthouse's lantern (LighthouseKit): a glass barrel of brass-framed prism
// rings with a bull's-eye panel per beam, turning with the rotor (LighthouseBeacon). The barrel's
// UV is (turns round it, height 0..1); panel k's centre is at turn k / beams, which the rotor's
// local +X carries. After dark the lamp inside lights it: every ring glows a little, and the panel
// facing the eye blazes - the flash you see from the shore is that panel lining up with you. The
// beam axis comes off MODEL_MATRIX, so nothing is set per frame. By day it is glass: dark, glossy,
// prisms catching the sky.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
uniform vec3 lamp_color = vec3(1.0, 0.93, 0.78);
uniform float beams = 2.0;
uniform float barrel_height = 1.4;
uniform float barrel_radius = 0.55;

varying vec3 v_axis;

void vertex() {
	v_axis = normalize(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec2 uv = UV;
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec2 e2 = normalize(vw.xz + vec2(1e-6, 0.0));
	vec2 a2 = normalize(v_axis.xz + vec2(1e-6, 0.0));
	float az = atan(a2.x * e2.y - a2.y * e2.x, dot(a2, e2));
	// Nearest panel centre to this fragment (in turns), and the flash of that panel at the eye.
	float k = floor(uv.x * beams + 0.5);
	float du = (uv.x - k / beams) * 6.2831853 * barrel_radius;
	float dv = (uv.y - 0.5) * barrel_height;
	float rr = length(vec2(du, dv));
	float flash = 0.0;
	for (int i = 0; i < 4; i++) {
		if (float(i) < beams) {
			flash += pow(max(cos(az - 6.2831853 * float(i) / beams), 0.0), 60.0);
		}
	}
	// Bull's-eye rings round the panel centre, prism belts above and below the middle.
	float bull = 0.5 + 0.5 * cos(rr * 46.0);
	float belt = 0.5 + 0.5 * cos(abs(dv) * 70.0);
	float in_eye = 1.0 - smoothstep(0.36, 0.42, rr);
	float pattern = mix(belt, bull, in_eye);
	// Brass frames between the panels and round the belts.
	float frame = 1.0 - smoothstep(0.0, 0.025, abs(fract(uv.x * beams + 0.5) - 0.5) * 2.0 * 3.14159 * barrel_radius / beams);
	frame = max(frame, 1.0 - smoothstep(0.0, 0.02, abs(abs(dv) - 0.42)));
	float night = clamp(lamp_factor, 0.0, 1.0);
	vec3 glass = vec3(0.05, 0.07, 0.07) * (0.7 + 0.6 * pattern);
	ALBEDO = mix(glass, vec3(0.55, 0.40, 0.16), frame);
	METALLIC = frame * 0.9;
	ROUGHNESS = mix(0.04, 0.35, frame);
	SPECULAR = 0.9;
	float lit = night * (0.35 + 0.65 * pattern) * (0.25 + 9.0 * flash * in_eye + 1.5 * flash);
	EMISSION = cs_out(lamp_color * lit * (1.0 - frame));
}
