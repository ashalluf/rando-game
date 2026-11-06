shader_type spatial;
render_mode cull_back;

// A car that has been hit: car_paint.gdshader with bullet holes, dents, scorch and fire damage
// compiled in (the code is car_paint.gdshaderinc under CAR_DAMAGE). Only a damaged car wears it:
// CarDamage copies the car's paint material onto this shader the first time it is hit, so an
// undamaged car pays for none of it.
#define CAR_DAMAGE
#include "res://shaders/car_paint.gdshaderinc"
