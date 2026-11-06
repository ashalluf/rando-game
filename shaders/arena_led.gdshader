shader_type spatial;
render_mode unshaded, shadows_disabled, cull_back;

// The arena district's architectural LED (ArenaNight, rc5-arena-night): the theatre's light
// blades, the parapet coves, the hotel's crown lantern and fins. Unshaded, the colour in the
// vertex colour as display (sRGB) numbers times `gain`, handed to the renderer in its own space
// (cs_as_uniform(): decoded on Forward+, as a StandardMaterial's albedo_color would be). Full after
// dark (lamp_factor), `day_level` of it by day: a facade's LED is on in daylight but reads as
// a dull line, never a glow.
// Shader files use // comments, never #.

#include "res://shaders/color_space.gdshaderinc"

global uniform float lamp_factor;

uniform float gain = 1.45;
uniform float day_level = 0.18;

void fragment() {
	vec3 c = COLOR.rgb * gain * mix(day_level, 1.0, clamp(lamp_factor, 0.0, 1.0));
	ALBEDO = cs_as_uniform(c);
}
