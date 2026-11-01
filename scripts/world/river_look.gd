class_name RiverLook
## The LA River from the bed (wave 5, refcam `la_river`, docs/HANDOFF.md "The LA River from the
## bed"): the `river_look` shader global the river's shaders read. 1 (the default) is the reviewed
## look: the low flow mirrors the channel's own banks and is turbid, the bed and banks keep their
## joints and stains at a grazing angle, the shaded bank takes the sunlit one's bounce; 0 is the old
## look exactly (`RIVER_LOOK=0` in the environment, the A/B). Also gates RiverDebris (litter, weeds).

static var _applied := false


static func enabled() -> bool:
	return OS.get_environment("RIVER_LOOK") != "0"


## Pushes the global once (RiverBuild calls it when it makes its materials).
static func apply() -> void:
	if _applied:
		return
	_applied = true
	RenderingServer.global_shader_parameter_set("river_look", 1.0 if enabled() else 0.0)
