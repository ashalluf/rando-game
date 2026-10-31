class_name WetRoadMirror
extends RefCounted
## The wet road's mirror at night (docs/HANDOFF.md "The wet road's mirror"): the lit city in a wet
## street drawn as long vertical streaks and smears under the shop fronts and windows, broken into
## glints by the asphalt, sharp only in standing water (shaders/wet_road_mirror.gdshaderinc, in
## road.gdshader). This is the switch: `WET_ROAD_MIRROR=0` in the environment sets the
## `wet_road_mirror` shader global to 0, and road.gdshader draws its old mirrored_city() (the A/B).
## A dry road never reaches either.

static var enabled: bool = OS.get_environment("WET_ROAD_MIRROR") != "0"


## Pushes the switch to the shaders (Weather._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("wet_road_mirror", 1.0 if enabled else 0.0)


## Turns it on or off at once (tests, stills).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()
