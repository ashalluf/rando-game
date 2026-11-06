extends SceneTree
## The taco truck refcam's probe (fleet wave 8, rc5-taco-truck-night): loads the city at a point
## and an hour, waits, then lists the taco trucks, their cooks, customers and the queue spots
## round it, and the crowd's room. Headless (plan and nodes only):
##   godot --headless --path . --script tools/rc5_taco_truck/probe.gd -- --spawn=553.6,344,0,0 --hour=23
## Env: R (metres, default 60), WAIT (frames, default 120).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	_run.call_deferred()


func _run() -> void:
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var wait := int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 120
	for i in wait:
		await process_frame
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 60.0
	var ws := root.get_node("/root/WorldState")
	var scene := current_scene
	print("ROOM ", scene.get("_crowd_room") if scene.get("_crowd_room") != null else "?")
	for ch in scene.get_children():
		if not ch.has_meta("vendor_trucks"):
			continue
		for t: Array in ch.get_meta("vendor_trucks"):
			var tw: Vector3 = ws.to_world(Vector3((t[0] as Vector2).x, 0, (t[0] as Vector2).y))
			if Vector2(tw.x, tw.z).distance_to(c) > reach:
				continue
			print("TRUCK chunk %s at %.1f,%.1f dir %s" % [ch.name, tw.x, tw.z, t[1]])
			print("  people planned ", (ch.get_meta("vendor_people", []) as Array).size())
			for q: Dictionary in ch.get_meta("vendor_queue", []):
				print("  queue %s taken %s" % [q.p, q.taken])
			for n in ch.get_children():
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("street_vendor.gd"):
					var w: Vector3 = ws.to_world(n.position)
					print("  VENDOR %s at %.1f,%.2f,%.1f truck=%s" % [n.name, w.x, w.y, w.z, n.get("in_truck")])
	quit()
