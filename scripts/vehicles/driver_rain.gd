class_name DriverRain
extends RefCounted
## The rain seen from the driver's seat (rc5-driver-rain, refcam `driver_rain` in
## tools/refcams/cameras_w8.json, docs/HANDOFF.md "The driver's seat in the rain"). The car the
## player sits in wears CarInterior's see-through glass (car_glass_open.gdshader), which had no rain
## on it at all: from inside, a downpour drew a dry, clear windscreen. `apply()` (one hook in
## CarInterior) turns on that shader's `rain_inside` block: car_glass_wet's beads, runs and wiper
## arcs, each bead refracting the street behind it from the screen texture. Both renderers.
## `DRIVER_RAIN=0` in the environment is the A/B (the pane as it was).

static var enabled: bool = OS.get_environment("DRIVER_RAIN") != "0"


## Puts the rain on CarInterior's glass material.
static func apply(glass: ShaderMaterial) -> void:
	if glass == null:
		return
	glass.set_shader_parameter("rain_inside", 1.0 if enabled else 0.0)
