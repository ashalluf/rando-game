shader_type spatial;

// The raised letters on a shop fascia: the relief standing in front of the name that
// shaders/building.gdshader paints on the board itself. They exist only for the near view - the
// painted name carries the sign at every distance and in the web build - so the one thing this
// has to get right is matching it, or a street full of shops changes brightness at the distance
// the letters cull out. It lights up with the street lamps for exactly that reason, and is a
// matte painted letter by day.
//
// The city's shopfronts (PropFactory.shop_sign_material()) also change colour after dark: a
// channel letter is cream by day and burns its own colour at night, a letter on a lit lightbox
// goes dark against it. night_mix 0 (the default) is the plain letter above, for everything else.

// Letter colour: cream on a dark board, near-black on a cream one.
uniform vec3 ink : source_color = vec3(0.94, 0.92, 0.87);
// How brightly the letters burn once the lamps are on. 0 is a shop that leaves its sign off.
uniform float glow = 1.15;
// The letter after dark, and how far it goes to it as the lamps come on.
uniform vec3 night_ink : source_color = vec3(0.94, 0.92, 0.87);
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;
// A faint emission kept by day (the shop names always carried one), faded out as the lamps come on.
uniform vec3 day_glow_color : source_color = vec3(1.0, 0.93, 0.78);
uniform float day_glow = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.38;
// 0 by day, 1 once the street lamps are on (night, or a dark enough storm).
global uniform float lamp_factor;

void fragment() {
	float lamp = clamp(lamp_factor, 0.0, 1.0);
	vec3 lit_ink = mix(ink, night_ink, night_mix);
	ALBEDO = mix(ink, lit_ink, lamp);
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
	EMISSION = day_glow_color * day_glow * (1.0 - lamp) + lit_ink * lamp * glow;
}
