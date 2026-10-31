shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The hero's hair and brows, the soft fringe under the core's alpha cut (hero-closeup-2): the
// next pass of hero_hair.gdshader's material, drawn blended over it. See hero_hair.gdshaderinc.
#define HAIR_LIGHT
#define HAIR_FRINGE
#include "res://shaders/hero_hair.gdshaderinc"
