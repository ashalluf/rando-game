shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
#include "res://shaders/color_space.gdshaderinc"

// Weeds where nobody mows (LawnsCloseup.weed_mesh(): crabgrass tufts, toothed rosettes, a
// flower on its stalk) in the pavement's joints and seams and along the yards' fences. The part's
// colour is the vertex colour, LINEAR (a vertex colour arrives raw on both renderers; the instance
// colour is white, Godot multiplies it in); INSTANCE_CUSTOM.r is how parched the weed is (0 green .. 1 summer-brown). Works in linear, out by
// cs_out(). UV.y is the height up the plant (the sway and the darker base).

global uniform float wind_factor;
global uniform float night_factor;
global uniform float road_wetness;

varying float height_t;
varying float parched;


void vertex() {
	height_t = clamp(UV.y, 0.0, 1.0);
	parched = INSTANCE_CUSTOM.r;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + world.x * 0.4 + world.z * 0.3) * 0.03 * max(wind_factor, 0.2) * height_t * height_t;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.4;
}


void fragment() {
	vec3 part = COLOR.rgb;
	float dry = clamp(parched, 0.0, 1.0);
	vec3 col = part;
	// A flower (bright yellow) stays a flower; leaves go brown with the summer.
	float leaf = 1.0 - step(0.5, part.r - part.b);
	col = mix(col, vec3(0.20, 0.15, 0.06), dry * 0.55 * leaf);
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.5, height_t));
	float wet = clamp(road_wetness, 0.0, 1.0);
	col *= mix(1.0, 0.8, wet);
	col *= 1.0 - 0.6 * clamp(night_factor, 0.0, 1.0);
	ALBEDO = cs_out(col);
	ROUGHNESS = mix(0.8, 0.3, wet);
	SPECULAR = 0.3;
	BACKLIGHT = cs_out(col * 0.25);
}
