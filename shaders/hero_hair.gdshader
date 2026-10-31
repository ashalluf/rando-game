shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The hero's hair and brows, the opaque core (alpha scissor) with the strand light: the code and
// notes are in hero_hair.gdshaderinc; hero_hair_fringe.gdshader is its next pass.
#define HAIR_LIGHT
#include "res://shaders/hero_hair.gdshaderinc"
