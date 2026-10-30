extends SceneTree
## How busy the street round the camera is (busy-streets pass), headless and fast:
##
##   godot --headless --path . --script tools/busy_streets/census.gd -- --spawn=2359.4,880,0,12,2 --hour=12
##
## Loads the city at the spawn and, every EVERY frames for FRAMES frames (60 fps physics), prints
## one CENSUS line: street cars moving within 150 m of the camera (and how many of them are in the
## view cone, CONE degrees either side of the camera's heading), cars standing (queued at a light,
## a stop sign or behind another) within 150 m, parked cars within 150 m, walkers within 60 m (in
## view), the whole traffic and crowd counts against their caps, and the pool. BUSY_STREETS=0 is
## the A/B. QUIT_AFTER=1 prints only the last line.
func _initialize() -> void:
	Engine.max_fps = 60
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 5:
		await process_frame
	var frames := int(_env("FRAMES", "1200"))
	var every := int(_env("EVERY", "200"))
	for f in frames:
		await process_frame
		if (f + 1) % every == 0:
			print(census_line(self, float(_env("CONE", "40"))))
	quit()


static func census_line(tree: SceneTree, cone_deg: float = 40.0) -> String:
	var c := census(tree, cone_deg)
	return "CENSUS t=%.1fs moving150=%d (view %d) queued150=%d parked150=%d walkers60=%d (view %d) traffic=%d/%d freeway=%d crowd=%d/%d pool=%d" % [
		Time.get_ticks_msec() / 1000.0, c.moving, c.moving_view, c.queued, c.parked, c.walkers, c.walkers_view,
		c.traffic, c.cap, c.freeway, c.crowd, c.crowd_cap, c.pool]


static func census(tree: SceneTree, cone_deg: float = 40.0) -> Dictionary:
	var out := {"moving": 0, "moving_view": 0, "queued": 0, "parked": 0, "walkers": 0, "walkers_view": 0,
		"traffic": 0, "cap": 0, "freeway": 0, "crowd": 0, "crowd_cap": 0, "pool": 0}
	var cam := tree.root.get_viewport().get_camera_3d()
	var player := tree.get_first_node_in_group("player") as Node3D
	var eye: Vector3 = cam.global_position if cam else (player.global_position if player else Vector3.ZERO)
	var fwd: Vector3 = -cam.global_transform.basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var cos_cone := cos(deg_to_rad(cone_deg))
	var tm := tree.root.find_child("Traffic", true, false)
	if tm:
		out.cap = tm.max_cars
		out.traffic = tm.cars.size()
		out.freeway = tm.freeway_cars.size()
		out.pool = tm._pool.size()
		for car in tm.cars:
			if not is_instance_valid(car) or not car.is_inside_tree():
				continue
			var d: Vector3 = car.global_position - eye
			d.y = 0.0
			if d.length() > 150.0:
				continue
			var v: float = car.traffic.get("v", 0.0) if car.traffic else 0.0
			if v < 0.5:
				out.queued += 1
			else:
				out.moving += 1
				if d.length() > 1.0 and d.normalized().dot(fwd) > cos_cone:
					out.moving_view += 1
	for n in tree.get_nodes_in_group("vehicle"):
		var car = n
		if car == null or not car.has_method("is_traffic") or car.is_traffic() or car.driver != null:
			continue
		var d: Vector3 = car.global_position - eye
		d.y = 0.0
		if d.length() <= 150.0:
			out.parked += 1
	var streamer := tree.root.find_child("City", true, false)
	if streamer and "max_pedestrians" in streamer:
		out.crowd_cap = streamer.max_pedestrians
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Node3D
		if p == null or not p.is_inside_tree() or not p.visible:
			continue
		out.crowd += 1
		var d := p.global_position - eye
		d.y = 0.0
		if d.length() <= 60.0:
			out.walkers += 1
			if d.length() > 1.0 and d.normalized().dot(fwd) > cos_cone:
				out.walkers_view += 1
	return out


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
