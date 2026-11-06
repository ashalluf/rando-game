class_name CarUnderside
extends RefCounted
## What a car is made of underneath and inside its arches: arch liners, struts and springs,
## subframes and arms, the exhaust run and its polished tips, the fuel tank, the rear axle
## (docs/HANDOFF.md "Cars at arm's length"). Each lofted road body has a second file,
## road_<name>_under.glb (tools/make_car_undersides.py), laid in the body .glb's own coordinates,
## so it is hung as a child of the placed model with no transform of its own. It is not one of
## the car's `_body_meshes` (damage, cabins and glass never see it), casts no shadow, and is drawn
## only to DRAW_DISTANCE (inside the near body's range): past that nobody sees under a car.
## One surface, one shared material for every car (shaders/car_underside.gdshader).
## `CAR_UNDERSIDE=0` in the environment leaves it off (the A/B).

static var enabled: bool = OS.get_environment("CAR_UNDERSIDE") != "0"
static var _material: ShaderMaterial = null
static var _scenes: Dictionary = {}

## How far a car's underside is drawn (never past the near body): past ~20 m a liner, a spring
## or a 7 cm exhaust tip is a few pixels in a shadow.
const DRAW_DISTANCE := 22.0

const SHADER := preload("res://shaders/car_underside.gdshader")


## The underside file for a body .glb path ("" when that body has none).
static func path_for(body_path: String) -> String:
	if not body_path.ends_with(".glb"):
		return ""
	var p := body_path.trim_suffix(".glb") + "_under.glb"
	return p if ResourceLoader.exists(p) else ""


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## Hangs the underside under `inst` (the body model, already scaled and placed). Returns the
## node, or null when off or there is none.
static func attach(inst: Node3D, body_path: String, draw_distance: float) -> Node3D:
	if not enabled or inst == null:
		return null
	var p := path_for(body_path)
	if p == "":
		return null
	if not _scenes.has(p):
		_scenes[p] = load(p)
	var scene: PackedScene = _scenes[p]
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	node.name = "Underside"
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_range_end = minf(draw_distance, DRAW_DISTANCE)
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.add_child(node)
	return node
