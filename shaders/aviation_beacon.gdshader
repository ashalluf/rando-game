shader_type spatial;
render_mode unshaded, cull_back;

// A near roof spire's red obstruction light (Building's "spire", NightSkyline.beacon_material()).
// It used to burn steady while the far mast's flashed (building_lod.gdshader kind 2): after dark
// it swells and fades 30-40 times a minute on the building's own phase and period, as the far one
// does on its own; by day it burns steady and dim. Off with the night pass (NIGHT_SKYLINE=0), it
// burns steady as before. The colour is linear, set as a Vector3 (a Color from script would be
// decoded again on Forward+).

global uniform float night_factor;
global uniform float night_skyline;
global uniform vec3 origin_shift;
uniform vec3 color = vec3(1.0, 0.25, 0.2);

varying flat float v_phase;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// The building's true world XZ: the same on every frame and through every origin shift.
	vec2 xz = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz + origin_shift.xz;
	v_phase = hash21(floor(xz * 0.5) + 7.3);
}

void fragment() {
	float ph = v_phase;
	float period = 1.5 + 0.7 * fract(ph * 13.7);
	float cyc = fract(TIME / period + ph);
	float flash = smoothstep(0.0, 0.12, cyc) * (1.0 - smoothstep(0.38, 0.62, cyc));
	float on = mix(1.0, 0.08 + 0.92 * flash * 1.25, night_factor * night_skyline);
	ALBEDO = color * on * (1.0 + 2.0 * night_factor * night_skyline);
}
