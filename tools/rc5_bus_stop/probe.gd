extends SceneTree
## Lists the bus stops (BigVehicles.block_stop) round a point, for framing the bus_stop_rain refcam:
##   godot --headless --path . --script tools/rc5_bus_stop/probe.gd -- --spawn=x,z,0,0
## R=metres (default 500). Each line: road axis / index / name, dir, the stop (where the bus's nose
## stands), the district, the kerb lateral and the shelter's rough point on the pavement.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var bv: GDScript = load("res://scripts/vehicles/big_vehicles.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 500.0
	var bi: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	for axis: int in [0, 1]:
		var base: int = bi.x if axis == 0 else bi.y
		var base_k: int = bi.y if axis == 0 else bi.x
		for di in range(-span, span + 1):
			var index: int = base + di
			for dk in range(-span, span + 1):
				var k: int = base_k + dk
				for dir: int in [1, -1]:
					var stop: float = bv.call("block_stop", plan, axis, index, k, dir)
					if is_nan(stop):
						continue
					var road: float = plan.road_pos(axis, index)
					var q := Vector2(road, stop) if axis == 0 else Vector2(stop, road)
					if q.distance_to(c) > reach:
						continue
					var w: float = plan.road_width(axis, index)
					print("STOP axis %d index %d (%s, %.0f m wide) dir %d stop %.1f at %.1f,%.1f district %s line %d dest %s" % [axis, index, plan.road_name(axis, index), w, dir, stop, q.x, q.y, str(plan.district_at(q)), int(bv.call("route_of", plan, axis, index)), bv.call("destination", plan, axis, index, dir)])
	quit()
