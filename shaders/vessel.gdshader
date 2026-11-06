shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// OceanTraffic's vessels (Vessel, VesselMesh): the marina's boat shader with BOAT_RIDE on - the
// hull rides the ocean's swell in phase with the water (sea_ride.gdshaderinc) and loses what is
// under its waterline far from the camera. See shaders/boat_body.gdshaderinc for the rest.
#define BOAT_RIDE
#include "res://shaders/boat_body.gdshaderinc"
