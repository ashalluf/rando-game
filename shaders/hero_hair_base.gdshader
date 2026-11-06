shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The hero's hair and brows as hero-face-2 left them (HERO_CLOSEUP_2=0, the A/B): the renderer's
// own lighting with the anisotropic lobe, no fringe pass. See hero_hair.gdshaderinc.
#include "res://shaders/hero_hair.gdshaderinc"
