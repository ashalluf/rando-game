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
	var reach := w * 60.0 + streak * w * 40.0 + 1.5
	var front := smoothstep(0.0, 0.25, w) if down < 0.0 else 1.0 - smoothstep(reach - 3.0, reach, down)
	var splash := (1.0 - smoothstep(0.35, 0.9, up)) * smoothstep(0.0, 0.15, w)
	var driven := 0.6 * smoothstep(0.45, 1.0, w)
	var raining := maxf(maxf(front * lerpf(0.8, 1.0, streak), splash), driven)
	var drying := dry(0.2 + 0.55 * streak + 0.5 * (1.0 - smoothstep(0.3, 1.2, up)), w)
	return lerpf(raining, drying, clampf(d, 0.0, 1.0))


# --- Under an umbrella ------------------------------------------------------------------------------

## Sheltered copies of the crowd's shared look materials (character and hair): the same material
## with `rain_shelter` 1, so a person under an open umbrella keeps dry shoulders and hair while the
## look stays one shared material for everybody else. Keyed by the material itself (looks live for
## the session).
static var _sheltered: Dictionary = {}


## Puts `ped` (a Pedestrian) under shelter or back in the rain (RainCrowd, when an umbrella opens
## or folds): swaps the character and crowd-hair materials on its meshes for their sheltered copies
## or back. Cheap to call every frame: it does nothing unless the state changes.
static func shelter(ped: Node, on: bool) -> void:
	if ped == null or bool(ped.get_meta("wet_shelter", false)) == on:
		return
	ped.set_meta("wet_shelter", on)
	for node in ped.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat == null or mat.shader == null:
			continue
		var path := mat.shader.resource_path
		if path != "res://shaders/character.gdshader" and path != "res://shaders/crowd_hair.gdshader":
			continue
		var is_copy := float(mat.get_shader_parameter("rain_shelter") if mat.get_shader_parameter("rain_shelter") != null else 0.0) > 0.5
		if on and not is_copy:
			mi.material_override = sheltered_material(mat)
		elif not on and is_copy and mat.has_meta("wet_dry_of"):
			mi.material_override = mat.get_meta("wet_dry_of")


## The sheltered copy of `mat` (made once).
static func sheltered_material(mat: ShaderMaterial) -> ShaderMaterial:
	if _sheltered.has(mat):
		return _sheltered[mat]
	var c := mat.duplicate() as ShaderMaterial
	c.set_shader_parameter("rain_shelter", 1.0)
	c.set_meta("wet_dry_of", mat)
	_sheltered[mat] = c
	return c
