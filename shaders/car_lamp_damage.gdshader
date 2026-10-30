shader_type spatial;
render_mode cull_disabled;

// A lamp slot (light_front / light_rear) once one of its lamps is shot out or crushed, or the car
// has burnt: the model's own lamp material with the broken side dark - the smashed lens gone and
// the grey reflector behind it showing - and everything sooted over in a fire. Only a damaged
// car wears it (CarDamage); the lit glow on the road is the separate NightLights mesh, which
// CarDamage swaps for one without the broken lamps.

#include "res://shaders/car_damage.gdshaderinc"

uniform vec3 lamp_albedo : source_color = vec3(0.95);
uniform float lamp_roughness = 0.1;
uniform vec3 lamp_emission : source_color = vec3(0.0);
uniform float lamp_emission_energy = 0.0;
// 1 where that side's lamp is broken: x the lamp on the -x side of the mesh, y the +x side.
uniform vec2 broken = vec2(0.0);
uniform float burnt = 0.0;

varying vec3 lp;


void vertex() {
	lp = VERTEX;
}


void fragment() {
	float b = lp.x < 0.0 ? broken.x : broken.y;
	float n = cd_noise3(lp * 90.0);
	// A few jagged shards of lens left in the rim.
	float shard = step(0.78, n) * b;
	vec3 alb = mix(lamp_albedo, mix(vec3(0.07, 0.07, 0.075), lamp_albedo * 0.8, shard), b);
	float rough = mix(lamp_roughness, mix(0.45, 0.12, shard), b);
	float metal = 0.35 * b * (1.0 - shard);
	vec3 emit = lamp_emission * lamp_emission_energy * (1.0 - b);
	float soot = clamp(burnt * 1.5, 0.0, 1.0);
	alb = mix(alb, vec3(0.03, 0.027, 0.024), soot);
	rough = mix(rough, 0.85, soot);
	emit *= 1.0 - soot;
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
