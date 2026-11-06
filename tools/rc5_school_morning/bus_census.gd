extends SceneTree
## rc5-school-morning: the school buses parked round the spawn, over time (headless):
##   godot --headless --path . --script tools/rc5_school_morning/bus_census.gd -- --spawn=-232,-415.5,160,0 --hour=7.83
func _initialize() -> void:
	Engine.max_fps = 60
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 5:
		await process_frame
	var frames := int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "900")
	for f in frames:
		await process_frame
		if (f + 1) % 150 == 0:
			var buses := []
			for n in get_nodes_in_group("vehicle"):
				if "body_type" in n and int(n.body_type) == 19:
					buses.append("%s%s" % [n.global_position + (root.get_node("/root/WorldState").world_offset as Vector3), " T" if n.is_traffic() else ""])
			var budget := root.get_node_or_null("/root/PhysicsBudget")
			print("BUSES f=%d n=%d bodies=%d/%d %s" % [f + 1, buses.size(), budget.call("active_body_count"), budget.get("max_active_bodies"), buses])
	quit()
