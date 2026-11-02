extends SceneTree
## Which cars cast their shadow from the full body (not the shadow twin), and why (perf-audit-5).
##
##   godot --headless --path . --script tools/perf_audit_5/car_shadow_probe.gd -- --spawn=1989,160,-6,-3,12 --hour=13
##
## Loads the city at the spawn, lets it run SETTLE frames (default 600), then for every Vehicle
## within 400 m of the camera prints a tally: the body meshes casting ON, by the car's state
## (body tier, physics processing, traffic, in the physics_prop group), and the near-wheel count.
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in int(OS.get_environment("SETTLE") if OS.get_environment("SETTLE") != "" else "600"):
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	var at: Vector3 = cam.global_position if cam else Vector3.ZERO
	var tally := {}
	var wheels_near := 0
	var wheels_lit := 0
	var cars := 0
	for n in root.get_tree().get_nodes_in_group("vehicle"):
		var car = n
		if not (car is Node3D) or not car.is_inside_tree() or car.get("_body_meshes") == null:
			continue
		var d: float = car.global_position.distance_to(at)
		if d > 400.0:
			continue
		cars += 1
		var on := 0
		for m in car.get("_body_meshes"):
			if is_instance_valid(m) and m.is_visible_in_tree() and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				on += 1
		for rig: Array in car.get("_wheel_rigs"):
			var mi := rig[1] as MeshInstance3D
			if mi and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				wheels_lit += 1
			if car.get("_wheel_near"):
				wheels_near += 1
		var key := "tier %d proc %s traffic %s prop %s %s" % [car.get("_body_tier"), car.is_physics_processing(), car.is_traffic(),
			car.is_in_group("physics_prop"), "CASTS" if on > 0 else "ok"]
		if not tally.has(key):
			tally[key] = [0, 0.0]
		tally[key][0] += 1
		tally[key][1] += d
	print("CARSHADOW cars %d within 400 m; wheel rigs flagged near %d, wheel meshes casting %d" % [cars, wheels_near, wheels_lit])
	for k in tally:
		print("CARSHADOW %-60s %4d cars, mean %.0f m" % [k, tally[k][0], tally[k][1] / maxf(tally[k][0], 1)])
	quit()
