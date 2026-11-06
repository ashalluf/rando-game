extends RefCounted
## The "person_closeup" reference camera's staging (tools/refcams/cameras_w6.json, `"stage":
## "person"`): one pedestrian standing on the pavement at arm's length from the lens, the frame a
## 2026 crowd close-up - face, hair, skin, the garments' fabric, the hands and the shoes in one
## shot. Loaded at run time (after the autoloads) by refcams_shot.gd, so it names Pedestrian.
##
## The row's `person` key (every field optional):
##   model  the crowd rig's file stem ("crowd_h"); default crowd_h
##   look   Pedestrian look index (0..23); default 0 (the rig's own clothes)
##   dist   metres from the eye to the person's feet, along the camera's heading; default 1.6
##   turn   degrees the person is turned off facing the lens (+ = their left); default 18
##   carry  CrowdLife.Carry name (none, call, text, cup, bag, smoke); default none (the idle)
## The person is found by searching seeds for one whose own style rolls give that rig and look and
## no hat or pack (so the rig's head and hair are what is judged), placed on the ground under the
## spot, held standing (the idle, or the carry's stand), marked no_trim, and every other walker
## within CLEAR metres of the line from the eye to them is hidden for the shot.
##
## Env knobs for framing work: PERSON_MODEL, PERSON_LOOK, PERSON_DIST, PERSON_TURN, PERSON_CARRY
## override the row; PERSON_SEED=n takes that seed as it is (no search).

const DEFAULT_MODEL := "crowd_h"
const CLEAR := 2.5
## The seed search starts here (any number; the same row finds the same person every run).
const SEED_BASE := 770000
const SEED_TRIES := 200000

## refcams_shot's _place() reads these (the mayhem stager's contract): no hero in this shot.
static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _made: Array = []
static var _hidden: Array = []


static func stage(tree: SceneTree, scene: Node, cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("person", {}) if row.get("person", null) is Dictionary else {}
	var model := _env_s("PERSON_MODEL", String(spec.get("model", DEFAULT_MODEL)))
	var look := int(_env_s("PERSON_LOOK", str(spec.get("look", 0))))
	var dist := float(_env_s("PERSON_DIST", str(spec.get("dist", 1.6))))
	var turn := deg_to_rad(float(_env_s("PERSON_TURN", str(spec.get("turn", 18.0)))))
	var carry := _carry_of(_env_s("PERSON_CARRY", String(spec.get("carry", "none"))))
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var eye := cam.global_position
	var spot := _ground(tree, eye + fwd * dist)
	var path := "res://assets/models/%s.glb" % model
	var seed_value := int(OS.get_environment("PERSON_SEED")) if OS.get_environment("PERSON_SEED") != "" \
		else seed_for(path, look)
	var ped := Pedestrian.new()
	ped.setup(Rect2(spot.x - 40.0, spot.z - 40.0, 80.0, 80.0), 4.0, seed_value)
	ped.pause_chance = 0.0
	ped.cross_chance = 0.0
	ped.life_spawn_chance = 0.0
	ped.life_chance = 0.0
	ped.jogger_share = Vector2.ZERO
	ped.dog_share = Vector2.ZERO
	ped.set_meta("no_trim", true)
	ped.position = spot + Vector3.UP * 0.02
	scene.add_child(ped)
	_made.append(ped)
	ped._pause_left = 1.0e6
	# Facing the lens (the visual's forward is -Z), turned by `turn`.
	var back := -fwd
	ped._visual.rotation.y = atan2(-back.x, -back.z) + turn
	if carry != CrowdLife.Carry.NONE:
		ped._carry = carry
		ped._start_stand(1.0e6)
	else:
		ped._play_idle()
	ped._speed = 0.0
	print("REFCAM person: %s look %d seed %d at %s, %.2f m, turned %.0f deg, carry %d (hat %d)" % [
		ped._model_path, ped._look, seed_value, str(WorldState.to_world(spot)), dist, rad_to_deg(turn),
		carry, ped._hat])
	for i in 20:
		await tree.process_frame
		place.call()
		ped.position = spot + Vector3.UP * 0.02
		_clear_line(tree, eye, spot, ped)


## After the shot: the staged person freed, the hidden walkers shown again.
static func unstage() -> void:
	for p in _made:
		if is_instance_valid(p):
			p.queue_free()
	_made.clear()
	for p in _hidden:
		if is_instance_valid(p):
			p.visible = true
	_hidden.clear()


## A seed whose style stream (Pedestrian._add_model's rolls, in order) deals `path` and `look`
## and then no accessory - pure, so a row finds the same person every run.
static func seed_for(path: String, look: int) -> int:
	var available: Array = []
	for p in Pedestrian.MODELS:
		if ResourceLoader.exists(p) and not (p in Pedestrian.VARIETY_MODELS and not Pedestrian.variety_on()):
			available.append(p)
	var want := available.find(path)
	if want < 0:
		push_error("person_stage: no crowd rig %s" % path)
		return SEED_BASE
	var r := RandomNumberGenerator.new()
	for s in range(SEED_BASE, SEED_BASE + SEED_TRIES):
		r.seed = hash([s, "style"])
		if r.randi() % available.size() != want:
			continue
		if r.randi() % Pedestrian.CHARACTER_LOOKS != look:
			continue
		for k in 5: # build x / tall / z, lean, gait
			r.randf()
		if r.randf() < 0.42: # Pedestrian.accessory_chance: a hat or a pack
			continue
		return s
	push_error("person_stage: no seed for %s look %d" % [path, look])
	return SEED_BASE


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


static func _carry_of(name: String) -> int:
	match name.to_lower():
		"call":
			return CrowdLife.Carry.CALL
		"text":
			return CrowdLife.Carry.TEXT
		"cup":
			return CrowdLife.Carry.CUP
		"bag":
			return CrowdLife.Carry.BAG
		"smoke":
			return CrowdLife.Carry.SMOKE
	return CrowdLife.Carry.NONE


static func _env_s(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback


static func _ground(tree: SceneTree, p: Vector3) -> Vector3:
	var space := tree.root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if hit else p
