extends RefCounted
## A camera row's optional `dog_walker` key (cameras_w8.json's suburb_night): one person walking a
## dog down the pavement toward the lens, so the frame holds the street's evening life whatever the
## crowd rolled. Loaded at run time (after the autoloads) by refcams_shot.gd, so it names Pedestrian.
##
##   {"dist": metres ahead of the eye along its heading, "side": metres to the right of that line,
##    "seed": the walker's seed (its rig, look, dog's breed), "away": true walks away from the lens}
## Every field is optional. The walker is a plain Pedestrian with dog_share 1 and nothing else to
## do (no stops, no crossing, no crowd life), placed on the ground there, walking toward (or away
## from) the lens and put back on its spot every frame, so the walk cycle plays and the dog
## (CrowdDog, at the owner's left on its lead) follows; every other walker within CLEAR metres of
## the line from the eye to it is hidden for the shot. The log prints REFCAM dog lines.

const CLEAR := 2.0

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _made: Array = []
static var _hidden: Array = []


static func stage(tree: SceneTree, scene: Node, cam: Camera3D, place: Callable, row: Dictionary) -> void:
	var spec: Dictionary = row.get("dog_walker", {}) if row.get("dog_walker", null) is Dictionary else {}
	var dist := float(spec.get("dist", 9.0))
	var side := float(spec.get("side", 0.0))
	var seed_value := int(spec.get("seed", 551201))
	var away := bool(spec.get("away", false))
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var eye := cam.global_position
	var spot := _ground(tree, eye + fwd * dist + right * side)
	var ped := Pedestrian.new()
	ped.setup(Rect2(spot.x - 40.0, spot.z - 40.0, 80.0, 80.0), 4.0, seed_value)
	ped.pause_chance = 0.0
	ped.cross_chance = 0.0
	ped.life_spawn_chance = 0.0
	ped.life_chance = 0.0
	ped.jogger_share = Vector2.ZERO
	ped.dog_share = Vector2.ONE
	ped.set_meta("no_trim", true)
	ped.position = spot + Vector3.UP * 0.02
	scene.add_child(ped)
	_made.append(ped)
	var heading := fwd if away else -fwd
	var goal := Vector2(spot.x, spot.z) + Vector2(heading.x, heading.z) * 60.0
	for i in 24:
		await tree.process_frame
		place.call()
		ped.position = spot + Vector3.UP * 0.02
		ped._target = goal
		ped._route = PackedVector2Array()
		ped._route_pending = false
		ped._pause_left = 0.0
		ped._visual.rotation.y = atan2(-heading.x, -heading.z)
		_clear_line(tree, eye, spot, ped)
	var dog: Node3D = ped.get("_dog")
	print("REFCAM dog walker: %s look %d seed %d at %s, dog %s at %s" % [ped._model_path, ped._look, seed_value,
		str(WorldState.to_world(spot)), dog.name if dog else "none",
		str(WorldState.to_world(dog.global_position)) if dog and dog.is_inside_tree() else "-"])


static func unstage() -> void:
	for p in _made:
		if is_instance_valid(p):
			var dog: Variant = p.get("_dog")
			if dog is Node and is_instance_valid(dog):
				(dog as Node).queue_free()
			p.queue_free()
	_made.clear()
	for p in _hidden:
		if is_instance_valid(p):
			p.visible = true
	_hidden.clear()


static func _clear_line(tree: SceneTree, eye: Vector3, spot: Vector3, keep: Node) -> void:
	var a := Vector2(eye.x, eye.z)
	var b := Vector2(spot.x, spot.z)
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Node3D
		if p == null or p == keep or not p.visible:
			continue
		var q := Vector2(p.global_position.x, p.global_position.z)
		var d := Geometry2D.get_closest_point_to_segment(q, a, b + (b - a).normalized() * 1.5).distance_to(q)
		if d < CLEAR:
			p.visible = false
			_hidden.append(p)


static func _ground(tree: SceneTree, p: Vector3) -> Vector3:
	var space := tree.root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if hit else p
