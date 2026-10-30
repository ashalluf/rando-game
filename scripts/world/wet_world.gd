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


# --- Mirrors of shaders/wet_surface.gdshaderinc (the checks hold the two together) ----------------

## ws_dry(): how wet a spot holding `hold` still is with `w` of the water left, once drying.
static func dry(hold: float, w: float) -> float:
	w = clampf(w, 0.0, 1.0)
	var t := (1.0 - clampf(hold, 0.0, 1.0)) * 0.85
	return smoothstep(t, t + 0.18, w) * smoothstep(0.005, 0.06, w)


## ws_wall(): a wall's wetness `down` metres under its top, `up` over its foot, on a column that
## carries `streak` of the water, at wetness `w` and drying `d`.
static func wall(down: float, up: float, streak: float, w: float, d: float) -> float:
	w = clampf(w, 0.0, 1.0)
	var reach := w * 34.0 + streak * w * 16.0 + 1.5
	var front := smoothstep(0.0, 0.25, w) if down < 0.0 else 1.0 - smoothstep(reach - 3.0, reach, down)
	var splash := (1.0 - smoothstep(0.35, 0.9, up)) * smoothstep(0.0, 0.15, w)
	var raining := maxf(front * lerpf(0.8, 1.0, streak), splash)
	var drying := dry(0.2 + 0.55 * streak + 0.3 * (1.0 - smoothstep(0.3, 1.2, up)), w)
	return lerpf(raining, drying, clampf(d, 0.0, 1.0))
