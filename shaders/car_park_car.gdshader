shader_type spatial;
render_mode cull_back;

// The car parks' parked cars (CarParkBuild): the real bodies' far twins in a MultiMesh, the car
// paint shader with each car's paint in INSTANCE_CUSTOM.rgb (sRGB, as Vehicle.PAINTS writes it)
// instead of the `paint` uniform, so one material serves every car of a body type.
#define PAINT_FROM_CUSTOM
#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/car_paint.gdshaderinc"
