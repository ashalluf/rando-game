// Shared by the ballpark's shaders (BallparkBuild): the globals DayNight publishes, the colour
// space helpers, the integer hash the lot's parked cars are rolled with (Ballpark.ihash() is the
// same function bit for bit, so the painted cars and the 3D ones agree), and the floodlight term.
//
// THE FLOODLIGHTS. The park has no shadow-casting lights; after dark (lamp_factor) every surface
// the light banks see is EMITTED as if lit by them - its own albedo times `flood`. That is what a
// night game is from the hills: the field and the stands glowing in a dark ravine. A handful of
// real OmniLights (desktop) add the light on the player and the cars.
//
// Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;
global uniform float night_factor;

uint bp_lowbias32(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

// 0..1 from two integers (Ballpark.ihash01()).
float bp_hash01(int a, int b) {
	uint h = bp_lowbias32(uint(a + 65536) * 7919u + uint(b + 65536));
	return float(h & 0xFFFFu) / 65535.0;
}

// The floodlights' strength after dark: they come on with the street lamps.
float bp_flood() {
	return smoothstep(0.05, 0.6, lamp_factor);
}

// A vertex colour (written as sRGB numbers) as linear light, on either renderer: vertex colours
// arrive raw on both.
vec3 bp_vcol(vec3 c) {
	return cs_srgb_to_linear(c);
}
