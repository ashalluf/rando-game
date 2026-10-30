shader_type spatial;
render_mode cull_disabled;

// A car's windscreen wipers (CarWipers): the two arms and their blades as one small mesh in the body
// mesh's space, built PARKED along the screen's foot; the vertex stage turns each about its pivot
// in the screen's plane by the angle car_wipers.gdshaderinc works out from TIME - the same angle the
// glass uses to clear its beads. COLOR.r is which wiper (0 / 1), COLOR.g the part (0 arm, 1 the
// rubber), COLOR.b the metal's satin share.

#include "res://shaders/wet_surface.gdshaderinc"
#include "res://shaders/car_wipers.gdshaderinc"

uniform vec3 arm_color : source_color = vec3(0.025, 0.025, 0.027);


void vertex() {
	float th = wiper_angle(TIME);
	if (th > 0.0) {
		vec3 pv = COLOR.r < 0.5 ? wiper_pivot_a : wiper_pivot_b;
		vec3 d = VERTEX - pv;
		float du = dot(d, wiper_u);
		float dv = dot(d, wiper_v);
		float dn = dot(d, wiper_n);
		float c = cos(th);
		float s = sin(th);
		VERTEX = pv + wiper_u * (du * c + dv * s) + wiper_v * (-du * s + dv * c) + wiper_n * dn;
		float nu = dot(NORMAL, wiper_u);
		float nv = dot(NORMAL, wiper_v);
		float nn = dot(NORMAL, wiper_n);
		NORMAL = wiper_u * (nu * c + nv * s) + wiper_v * (-nu * s + nv * c) + wiper_n * nn;
	}
}


void fragment() {
	float rubber = COLOR.g;
	ALBEDO = mix(arm_color, vec3(0.012), rubber);
	ROUGHNESS = mix(0.42, 0.7, rubber);
	METALLIC = mix(0.35 * COLOR.b, 0.0, rubber);
	SPECULAR = 0.5;
	if (ws_on()) {
		float wet = ws_wet(0.3);
		ROUGHNESS = mix(ROUGHNESS, 0.12, wet);
	}
}
