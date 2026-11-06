extends RefCounted
## A camera row's optional `hill_car` key (cameras_w8.json's switchback_night): an ordinary car
## standing on a hill road with its lamps lit (a driver in the cabin), so the frame holds a pair of
## headlights on the switchback's next leg whatever the traffic rolled (no traffic drives the hill
## roads). Loaded at run time by refcams_shot.gd (after the autoloads).
##
##   {"at": [x, z], "toward": [x, z], "seed": n}
## at / toward TRUE world points on the road: the car stands at `at` nosed toward `toward`, on the
## road's top found by a ray, pitched to the grade. `seed` picks the car (Vehicle.random_car on a
## generator of that seed). The log prints REFCAM hill_car lines.

static var _car: Node3D = null


static func stage(tree: SceneTree, scene: Node, row: Dictionary) -> void:
	var spec: Dictionary = row.get("hill_car", {}) if row.get("hill_car", null) is Dictionary else {}
	if spec.is_empty():
		return
	var at := Vector2(float(spec.at[0]), float(spec.at[1]))
	var to := Vector2(float(spec.toward[0]), float(spec.toward[1]))
	var dir := (to - at).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 7))
	var vehicle_script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var car: Node3D = vehicle_script.call("random_car", rng)
	# Placed, not driven: kinematic, with a traffic record nobody's loop drives ("parked": the foot
	# off the brake, so the tail lamps are not brake lamps), which also seats a driver.
	car.set("traffic", {"placed": true, "parked": true, "speed": 0.0, "v": 0.0})
	(car as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	(car as RigidBody3D).freeze = true
	scene.add_child(car)
	await tree.process_frame
	var ws: Node = tree.root.get_node("/root/WorldState")
	var space := car.get_world_3d().direct_space_state
	var ys := []
	for k in [-2.0, 0.0, 2.0]:
		var p: Vector2 = at + dir * float(k)
		var top: Vector3 = ws.call("to_local", Vector3(p.x, 400.0, p.y))
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 500.0, 1)
		q.exclude = [(car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		ys.append(float((ws.call("to_world", hit.position) as Vector3).y) if not hit.is_empty() else NAN)
	var y := float(ys[1])
	if is_nan(y):
		print("REFCAM hill_car: no ground under %s" % str(at))
		return
	var pitch := atan2(float(ys[2]) - float(ys[0]), 4.0) if not (is_nan(float(ys[0])) or is_nan(float(ys[2]))) else 0.0
	var yaw := atan2(-dir.x, -dir.y)
	# The hill road strip lies CanyonRoad.LIFT over the carved ground the ray hits.
	var lift := float(car.call("road_lift")) + 0.26
	car.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), ws.call("to_local", Vector3(at.x, y + lift, at.y)))
	car.set("traffic_speed", 0.0)
	_car = car
	if OS.get_environment("SB_DEBUG") != "":
		await _debug(tree, ws)
	print("REFCAM hill_car: %s at %.1f,%.1f,%.1f yaw %.0f pitch %.1f lights %s" % [car.name, at.x, y + lift, at.y, rad_to_deg(yaw), rad_to_deg(pitch), str(car.call("lights_running"))])


static func unstage() -> void:
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null


## SB_DEBUG=x,y,z (TRUE world): every drawn geometry whose box holds that point, by path.
static func _debug(tree: SceneTree, ws: Node) -> void:
	var c := OS.get_environment("SB_DEBUG").split(",")
	var at: Vector3 = ws.call("to_local", Vector3(float(c[0]), float(c[1]), float(c[2])))
	var stack: Array[Node] = [tree.root]
	var hits: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for k in n.get_children():
			stack.append(k)
		var g := n as GeometryInstance3D
		if g and g.is_visible_in_tree():
			var box := g.global_transform * g.get_aabb()
			if box.grow(0.5).has_point(at) and box.size.length() < 400.0:
				print("SB_DEBUG %s %s size %s" % [g.get_path(), g.get_class(), str(box.size)])
				hits.append(g)
	# The terrain tile and the road strip round the point (TRUE world).
	var wp := Vector2(float(c[0]), float(c[2]))
	for ch in tree.root.find_children("Chunk_*", "", true, false):
		if not ch.has_method("owned_rect"):
			continue
		var r: Rect2 = ch.call("owned_rect")
		if not r.has_point(wp):
			continue
		var n: int = int(ch.get("_tile_n"))
		var hs: PackedFloat32Array = ch.get("_tile_heights")
		var plan: Variant = ch.get("plan")
		var i := int(floor((wp.x - r.position.x) / r.size.x * n))
		var j := int(floor((wp.y - r.position.y) / r.size.y * n))
		print("SB_TILE %s rect %s n %d ij %d,%d" % [ch.name, str(r), n, i, j])
		for dj in range(-1, 3):
			var line := ""
			for di in range(-1, 3):
				var k := (j + dj) * (n + 1) + (i + di)
				var vx := r.position.x + r.size.x * (i + di) / n
				var vz := r.position.y + r.size.y * (j + dj) / n
				line += " %.2f/%.2f" % [hs[k], float(plan.call("height_at", Vector2(vx, vz)))]
			print("SB_TILE row %d %s" % [dj, line])
	for ch in tree.root.find_children("Chunk_*", "", true, false):
		var road := ch.get_node_or_null("HillRoad") as MeshInstance3D
		var plan: Variant = ch.get("plan")
		if road and plan:
			var arr := road.mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var seen := {}
			for v in vs:
				var tw: Vector3 = ws.call("to_world", road.global_transform * v)
				var key := "%.1f,%.1f" % [tw.x, tw.z]
				if Vector2(tw.x, tw.z).distance_to(wp) < 10.0 and not seen.has(key):
					seen[key] = true
					print("SB_ROAD %s local %.2f,%.2f,%.2f world %.2f,%.2f,%.2f ground %.2f" % [ch.name, v.x, v.y, v.z, tw.x, tw.y, tw.z, float(plan.call("height_at", Vector2(tw.x, tw.z)))])
		var ter := ch.get_node_or_null("Terrain") as MeshInstance3D
		if ter and ch.has_method("owned_rect") and (ch.call("owned_rect") as Rect2).grow(5.0).has_point(wp):
			print("SB_TER %s xform %s" % [ch.name, str(ter.global_transform.origin)])
	# SB_AB=<dir>: the frame again with each of them hidden in turn (<dir>/sb_ab_<i>.png).
	var out := OS.get_environment("SB_AB")
	if out == "":
		return
	for i in hits.size():
		var g: GeometryInstance3D = hits[i]
		g.visible = false
		for f in 3:
			await tree.process_frame
		tree.root.get_texture().get_image().save_png(out.path_join("sb_ab_%d.png" % i))
		print("SB_AB %d hid %s" % [i, g.get_path()])
		g.visible = true
