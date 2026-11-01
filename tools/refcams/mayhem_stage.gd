extends RefCounted
## The "mayhem" reference camera's staging (tools/refcams/cameras_w5.json, `"stage": "mayhem"`):
## a combat moment on a midtown street at 18:00, framed like an action game's screenshot - the
## hero in the foreground with his rifle up, a parked car going up in a fuel fireball ahead of
## him, a wreck already burning behind it under its smoke, police cruisers across the street with
## their bars flashing and their crews firing, the crowd running. Loaded at run time (after the
## autoloads) by refcams_shot.gd, so it names Police, Pedestrian and Vehicle freely.
##
## Everything is placed in the camera's frame (forward along the street, right across it), from
## the numbers below; nothing is rolled from the global rng except the cars' looks, which are
## seeded (MAYHEM_SEED). The effect clock is stepped the way fx_shot.gd steps it (the effect's own
## elapsed time, never the wall clock) to FX_TIME into the blast, and the caller then holds the
## clock all but stopped for the settle frames.
##
## Env knobs for framing work (all optional): MAYHEM_FX_TIME (seconds into the fireball, default
## 0.3), MAYHEM_STARS (3), MAYHEM_NO_POLICE=1, MAYHEM_NO_CAR=1, MAYHEM_NO_WRECK=1.

## Where things stand, metres along the camera's forward (x) and to its right (y), from the eye.
const HERO := Vector2(4.6, -1.3)
const CAR := Vector2(18.0, 3.4)
const WRECK := Vector2(34.0, -6.0)
## Civilians put on both pavements this far ahead (metres), who panic and run at the camera.
const RUNNERS := [16.0, 19.0, 22.0, 25.0, 28.0, 31.0, 34.0, 38.0, 42.0, 46.0]
static var _made: Array = []
## The panic: an alarm this far round the blast spot, before the police have even stopped.
const PANIC_RADIUS := 90.0
## Where the panic starts (metres ahead): beyond the runners, so they run back at the camera.
const PANIC_FROM := 75.0
const MAYHEM_SEED := 4242

## The hero's spot (local), facing yaw; set by stage(), read by refcams_shot's _place() each frame.
static var hero_at := Vector3.INF
static var hero_yaw := 0.0


static func stage(tree: SceneTree, scene: Node, cam: Camera3D, player: Node3D, place: Callable) -> void:
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var eye := cam.global_position
	hero_yaw = atan2(-fwd.x, -fwd.z)
	hero_at = _ground(tree, eye + fwd * HERO.x + right * HERO.y)
	_tough(player)
	place.call()
	var rig := player.get_node_or_null("CameraRig")
	if rig:
		rig.call("set_look", rad_to_deg(hero_yaw), 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = MAYHEM_SEED
	var parent := player.get_parent()
	# The wreck first: blown up now, it is burning and smoking by the time of the shot.
	if OS.get_environment("MAYHEM_NO_WRECK") != "1":
		var wreck := _car(tree, parent, rng, eye + fwd * WRECK.x + right * WRECK.y, hero_yaw + 0.9)
		for i in 3:
			await tree.process_frame
			place.call()
		wreck.call("damage_state").explode()
	_runners(tree, scene, eye, fwd)
	for i in 2:
		await tree.physics_frame
	# The street panics before the police arrive (gunfire up the street), so people are running.
	Pedestrian.alarm(tree, eye + fwd * PANIC_FROM, PANIC_RADIUS, 6, true, "")
	var police := scene.get_node_or_null("Police")
	if police and OS.get_environment("MAYHEM_NO_POLICE") != "1":
		police.set("enabled", true)
		police.call("stage_for_shot", int(_f("MAYHEM_STARS", 3.0)), "standoff")
	for i in 30:
		await tree.process_frame
		place.call()
		_tough(player)
		if police:
			police.call("report_sighting")
		if rig:
			rig.call("set_look", rad_to_deg(hero_yaw), 0.0)
		if i == 10:
			Input.action_press("alt_fire")
	# The car in the foreground goes up, the clock slowed so the fireball is caught growing.
	var car: Node3D = null
	if OS.get_environment("MAYHEM_NO_CAR") != "1":
		car = _car(tree, parent, rng, eye + fwd * CAR.x + right * CAR.y, hero_yaw - 1.2)
		for i in 3:
			await tree.process_frame
			place.call()
	Engine.time_scale = 0.375
	if car:
		car.call("damage_state").explode()
	if police:
		for o in police.get("officers"):
			if is_instance_valid(o) and o.get("police") != null:
				var target: Vector3 = police.call("player_aim_point")
				o.call("_shoot", target, (o as Node3D).global_position.distance_to(target))
	# The hero answers: his rifle's flash and tracers in the frame.
	Input.action_press("fire")
	var want := _f("MAYHEM_FX_TIME", 0.3)
	var elapsed := 0.0
	while elapsed < want:
		await tree.process_frame
		elapsed += tree.root.get_process_delta_time()
		place.call()
		_tough(player)
	Input.action_release("fire")
	for w: Node3D in _made:
		if is_instance_valid(w):
			print("MAYHEM runner %s at %s panic %.1f visible %s" % [w.name, WorldState.to_world(w.global_position), float(w.get("_panic_left")), w.is_visible_in_tree()])
		else:
			print("MAYHEM runner gone")
	if OS.get_environment("MAYHEM_DUMP") == "1":
		_dump(tree, eye + fwd * CAR.x + right * CAR.y)
	print("MAYHEM staged: hero %s, car %s, %d cruisers, %d officers, fx %.2f s" % [WorldState.to_world(hero_at),
		WorldState.to_world(car.global_position) if car else Vector3.ZERO,
		(police.get("cruisers") as Array).size() if police else 0, (police.get("officers") as Array).size() if police else 0, elapsed])


## Walkers on the pavements either side of the street ahead (the block rings the camera's street
## runs between), alternating sides, so the alarm sends them running back past the hero.
static func _runners(tree: SceneTree, scene: Node, eye: Vector3, fwd: Vector3) -> void:
	var plan: CityPlan = scene.get("plan")
	var chunks: Dictionary = scene.get("chunks")
	if plan == null or chunks == null:
		return
	var right := fwd.cross(Vector3.UP).normalized()
	var k := 0
	for d: float in RUNNERS:
		var side := 1.0 if k % 2 == 0 else -1.0
		var probe := WorldState.to_world(eye + fwd * d + right * side * 9.0)
		var at2 := Vector2(probe.x, probe.z)
		var b := plan.block_index_at(at2)
		var rect: Rect2 = plan.block(b.x, b.y).rect
		# The pavement edge nearest the camera's street: the rect's side facing the eye's line.
		var e := WorldState.to_world(eye)
		var p := Vector2(clampf(at2.x, rect.position.x + 1.5, rect.end.x - 1.5), clampf(at2.y, rect.position.y + 1.5, rect.end.y - 1.5))
		if absf(fwd.x) > absf(fwd.z):
			p.y = rect.position.y + 2.0 if absf(e.z - rect.position.y) < absf(e.z - rect.end.y) else rect.end.y - 2.0
		else:
			p.x = rect.position.x + 2.0 if absf(e.x - rect.position.x) < absf(e.x - rect.end.x) else rect.end.x - 2.0
		var chunk: Node = chunks.get(plan.chunk_index_at(rect.get_center()))
		k += 1
		if chunk == null:
			continue
		var w := Pedestrian.new()
		w.setup(rect, plan.sidewalk_width, 88100 + k)
		w.pause_chance = 0.0
		w.cross_chance = 0.0
		w.set_meta("no_trim", true)
		w.position = Vector3(p.x, chunk.call("ground_y", p.x, p.y) + 0.1, p.y)
		chunk.add_child(w)
		_made.append(w)


## MAYHEM_DUMP=1: every flat thing drawn near the car's spot, to name a surface in the still.
static func _dump(tree: SceneTree, at: Vector3) -> void:
	for gi in tree.root.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box := g.global_transform * g.get_aabb()
		if box.size.x > 40.0 or box.size.z > 40.0 or box.size.y > 3.0:
			continue
		var c := box.get_center()
		if Vector2(c.x - at.x, c.z - at.z).length() > 9.0:
			continue
		var mat: Material = g.material_override
		if mat == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			mat = (g as MeshInstance3D).get_active_material(0)
		var what: String = mat.resource_name if mat else "-"
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
			what = (mat as ShaderMaterial).shader.resource_path
		print("MAYHEM_DUMP %s %s size %s at %s mat %s" % [g.get_path(), g.get_class(), box.size, c, what])


## A seeded random road car parked at `at` (local), turned to `yaw`.
static func _car(tree: SceneTree, parent: Node, rng: RandomNumberGenerator, at: Vector3, yaw: float) -> Vehicle:
	var car := Vehicle.random_car(rng)
	parent.add_child(car)
	car.global_position = _ground(tree, at) + Vector3.UP * 0.6
	car.rotation.y = yaw
	return car


## The ground under a local point (a world-layer ray from above), or the point itself.
static func _ground(tree: SceneTree, p: Vector3) -> Vector3:
	var space := tree.root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if hit else p


## The hero takes the police's rounds and the blast without going down (a still, not a fight).
static func _tough(player: Node3D) -> void:
	var h: Node = player.get("health")
	if h:
		h.set("max_health", 1.0e9)
		h.set("health", 1.0e9)


static func _f(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
