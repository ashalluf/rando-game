shader_type spatial;
render_mode cull_back;

// Car paint. The code lives in car_paint.gdshaderinc so the damage variant
// (car_paint_damage.gdshader) is the same shader with the damage compiled in.
#include "res://shaders/car_paint.gdshaderinc"
