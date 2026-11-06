shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// The body is shaders/boat_body.gdshaderinc (shared with vessel.gdshader, which rides the sea).
#include "res://shaders/boat_body.gdshaderinc"
