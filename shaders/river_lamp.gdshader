shader_type spatial;
render_mode cull_back;

// The lit parts of the river's bridges (RiverBridges): lantern globes, cobra-head lenses, the
// tied arch's LED strips. By day frosted glass (or white paint on the arch); after dark it glows
// in its own colour, carried in the vertex colour (LINEAR), by `lamp_factor` - DayNight's lamp
// level, which also brings it on in a storm. COLOR.a is how much it glows (0 never: a painted
// part riding in the same mesh).

global uniform float lamp_factor;

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 day_color = vec3(0.62, 0.62, 0.60);
uniform float glow = 5.5;

void fragment() {
	float on = COLOR.a * smoothstep(0.05, 0.6, lamp_factor);
	ALBEDO = cs_out(mix(day_color, COLOR.rgb * 0.6, COLOR.a * 0.5));
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	EMISSION = cs_out(COLOR.rgb * glow * on);
}
