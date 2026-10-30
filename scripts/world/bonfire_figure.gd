class_name BonfireFigure
extends BeachFigure
## One of the people sitting round a beach fire after dark (Bonfires): a beach figure (posed
## once, baked, merged per chunk - BeachFigure / CampFigure) in STREET CLOTHES rather than a
## swimsuit, in the crowd rig's own outfit with a clean look (Pedestrian.character_material(), not
## RoughSleeper's worn one). Shot, knocked or near gunfire it wakes into a live BeachGoer with
## `clothed` set, which gets up and runs like any sunbather and is dressed the same way when it
## goes down (BeachGoer.knock()).

## The crowd rig (an index into Pedestrian.MODELS).
var model: int = 0

## Bakes by "seed|pose|key" (null where there is no mesh data).
static var _fire_baked: Dictionary = {}


## The live person in this figure's place.
func wake() -> RoughSleeper:
	if _awake or collision_layer == 0 or chunk == null or not is_instance_valid(chunk):
		return null
	_awake = true
	collision_layer = 0
	if figure_mesh and is_instance_valid(figure_mesh):
		figure_mesh.hide_figure(figure_index)
	if chunk.has_method("_take_crowd_room"):
		chunk._take_crowd_room()
	var ped := BeachGoer.new()
	ped.clothed = true
	ped.setup_sleeper(ring, sidewalk, seed_value, pose, home, yaw)
	ped.beach_pose = beach_pose
	ped.lift = lift
	ped.position = Vector3(home.x, BeachLife.ground_at(chunk, home.x, home.y, position.y) + lift, home.y)
	chunk.add_child(ped)
	queue_free()
	return ped


## Puts every skinned body under `rig` back in street clothes with the clean look `look`, and the
## hair in its own colour (BeachGoer's _ready() and knock() call this for a clothed person, where
## the beach would put a swimsuit on).
static func clothe(rig: Node, look: int) -> void:
	if rig == null:
		return
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.skin or Pedestrian.is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := Pedestrian.character_material(src.albedo_texture, look)
			if mat:
				mi.material_override = mat
	Pedestrian.plain_hair(rig)


## The figure mesh of person `seed` (crowd rig `model`) in `pose_kind` / `pose_key`, clothed (feet
## at the origin, facing -Z); baked once, null without mesh data.
static func bonfire_mesh(seed: int, pose_kind: int, pose_key: String, model: int) -> Mesh:
	var key := "%d|%d|%s" % [seed, pose_kind, pose_key]
	if _fire_baked.has(key):
		return _fire_baked[key]
	var host := BeachFigure._bake_parent()
	if host == null:
		return null
	_fire_baked[key] = null
	var ped := BeachGoer.new()
	ped.clothed = true
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, seed, pose_kind, Vector2.ZERO, 0.0)
	ped.beach_pose = pose_key
	host.add_child(ped)
	if ped._visual:
		ped._visual.scale = Vector3.ONE
		ped._visual.position = Vector3.ZERO
	BeachFigure._refresh(ped)
	var near := CampFigure._bake(ped, Pedestrian.mid_triangles)
	if near:
		var far := CampFigure._bake(ped, Pedestrian.far_triangles)
		if far:
			CampFigure._shadows[near] = far
	BeachFigure._drop(ped)
	_fire_baked[key] = near
	return near


## What the loading screen bakes: every bonfire rig in every bonfire pose ([model, pose, key]).
static func kinds() -> Array:
	var out: Array = []
	if not Bonfires.enabled:
		return out
	for m: int in Bonfires.MODELS:
		for r: Array in Bonfires.POSES:
			out.append([m, int(r[1]), String(r[2])])
	return out


static func warm_kind(k: Array) -> void:
	bonfire_mesh(BeachGoer.seed_for(int(k[0]), 7), int(k[1]), String(k[2]), int(k[0]))
