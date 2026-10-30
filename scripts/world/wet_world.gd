class_name WetWorld
extends RefCounted
## The world in the rain (docs/HANDOFF.md "The wet world"): every surface that is not a road takes
## Weather's water - car paint and glass (beads, runs, wipers: CarWipers), building walls darkening
## from the top down with streaks, roofs and awnings glossy, the crowd's shoulders and hair, the far
## city in step. All of it is in the shaders (shaders/wet_surface.gdshaderinc), driven by the
## `road_wetness` / `road_drying` / `rain_intensity` globals Weather already publishes; this is the
## switch. `WET_WORLD=0` in the environment turns it off (the A/B): the `wet_world` shader global
## goes to 0 and no wipers are built.

static var enabled: bool = OS.get_environment("WET_WORLD") != "0"


## Pushes the switch to the shaders (Weather._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("wet_world", 1.0 if enabled else 0.0)


## Turns the wet world on or off at once (tests): shaders and new wipers alike.
static func set_enabled(on: bool) -> void:
	enabled = on
	install()
