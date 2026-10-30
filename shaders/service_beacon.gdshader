shader_type spatial;
// A service vehicle's amber warning lenses (ServiceVehicles.beacon_material()): LED strobes in a
// double flash, the left and right banks half a cycle apart and the front and back a quarter, so
// a light bar walks rather than blinks in step. Which bank a lens is in comes from where it sits
// in the model (the vertex's model-space position), so one shared material serves every lens of
// every truck. `active` 0 leaves them dark (the ice-cream truck's pair while it drives).
// Amber is held at green ~0.42 of red: brighter, AgX walks it toward yellow-white.

#include "res://shaders/color_space.gdshaderinc"

uniform float active = 1.0;
uniform float rate = 1.35;
uniform float energy = 5.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float flash(float t) {
	t = fract(t);
	return step(t, 0.07) + step(0.14, t) * step(t, 0.21);
}

void fragment() {
	float bank = (lp.x > 0.0 ? 0.5 : 0.0) + (lp.z > 0.0 ? 0.25 : 0.0);
	float on = clamp(flash(TIME * rate + bank), 0.0, 1.0) * active;
	vec3 amber = vec3(1.0, 0.42, 0.03);
	// The lens's fresnel-ish rim and the LED dots behind it.
	float dots = 0.75 + 0.25 * step(0.5, fract(lp.x * 40.0)) * step(0.5, fract(lp.y * 40.0 + lp.z * 40.0));
	ALBEDO = cs_out(amber * 0.32);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	EMISSION = cs_out(amber * (on * energy * dots + 0.05 * active));
}
