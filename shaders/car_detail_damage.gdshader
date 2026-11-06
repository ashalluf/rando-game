shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// A crashed car's plates and badges (CrashDeform): car_detail.gdshader moved with the crush.
#define CRASH_DETAIL
#include "res://shaders/car_detail.gdshaderinc"
