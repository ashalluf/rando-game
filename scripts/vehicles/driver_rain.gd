class_name DriverRain
extends RefCounted
## The rain seen from the driver's seat (rc5-driver-rain, refcam `driver_rain` in
## tools/refcams/cameras_w8.json, docs/HANDOFF.md "The driver's seat in the rain"). The car the
## player sits in wears CarInterior's see-through glass (car_glass_open.gdshader), which had no rain
## on it at all: from inside, a downpour drew a dry, clear windscreen. `apply()` (one hook in
## CarInterior) turns on that shader's `rain_inside` block: car_glass_wet's beads, runs and wiper
## arcs, each bead refracting the street behind it from the screen texture. Both renderers.
## `DRIVER_RAIN=0` in the environment is the A/B (the pane as it was).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("DRIVER_RAIN") != "0"


## How much street light the cabin catches at night (car_interior.gdshader `night_fill`).
const NIGHT_FILL := 0.12


## Puts the rain on CarInterior's glass material and the night look on its cabin material.
static func apply(glass: ShaderMaterial, cabin: ShaderMaterial = null) -> void:
	if glass != null:
		glass.set_shader_parameter("rain_inside", 1.0 if enabled else 0.0)
	if cabin != null:
		cabin.set_shader_parameter("night_fill", NIGHT_FILL if enabled else 0.0)
		cabin.set_shader_parameter("night_screens", 1.0 if enabled else 0.0)


## Where car lamp halos come in (m; car_lights.gdshader `halo_near`, set by
## PropFactory.vehicle_light_material()): 0 with the look off.
static func halo_near() -> float:
	return 12.0 if enabled else 0.0


## Turns the whole look on or off on `car`'s built cabin (tools: a same-frame A/B).
static func look(car: Node, on: bool) -> void:
	var was := enabled
	enabled = on
	for ci in car.find_children("CarInterior", "", true, false):
		apply(ci.get("_glass"), ci.get("_mat"))
	for key: String in PropFactory._cache:
		if key.begins_with("car_light_mat_"):
			(PropFactory._cache[key] as ShaderMaterial).set_shader_parameter("halo_near", halo_near())
	enabled = was
