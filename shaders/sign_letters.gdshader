shader_type spatial;

// The raised letters on a shop fascia: the relief standing in front of the name that
// shaders/building.gdshader paints on the board itself. They exist only for the near view - the
// painted name carries the sign at every distance and in the web build - so the one thing this
// has to get right is matching it, or a street full of shops changes brightness at the distance
// the letters cull out. It lights up with the street lamps for exactly that reason, and is a
// matte painted letter by day.

// Letter colour: cream on a dark board, near-black on a cream one.
uniform vec3 ink : source_color = vec3(0.94, 0.92, 0.87);
// How brightly the letters burn once the lamps are on. 0 is a shop that leaves its sign off.
uniform float glow = 1.15;
// 0 by day, 1 once the street lamps are on (night, or a dark enough storm).
global uniform float lamp_factor;

void fragment() {
	ALBEDO = ink;
	ROUGHNESS = 0.38;
	SPECULAR = 0.5;
	EMISSION = ink * lamp_factor * glow;
}
