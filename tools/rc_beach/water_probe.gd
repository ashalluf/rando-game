extends SceneTree
## Lists every BeachActivity near the spawn and the people it put in the water (where, what mesh,
## visible). Needs mesh data, so opengl3 under Xvfb:
##   xvfb-run -a godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/rc_beach/water_probe.gd -- --spawn=-732,800,105,-4 --hour=14 --nohud
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 60:
		await process_frame
	var n := 0
	for act in _find(root, "BeachActivity"):
		var water: Array = act.get("_water")
		var counts: Dictionary = act.get("_counts")
		print("ACT chunk=%s z=%.0f..%.0f counts=%s water=%d" % [act.get_parent().name, act.get("z0"), act.get("z1"), str(counts), water.size()])
		for w: Dictionary in water:
			var node: Node3D = w.node
			var wp: Vector3 = root.get_node("/root/WorldState").call("to_world", node.global_position)
			var body := node.get_child(0) as MeshInstance3D
			print("  %s state=%s at=%.1f,%.2f,%.1f vis=%s mesh=%s" % [w.kind, w.get("state", ""), wp.x, wp.y, wp.z, node.is_visible_in_tree(), body.mesh != null])
			n += 1
	print("WATER_PEOPLE ", n)
	# LOOK=swim|wade|surf: a camera 7 m off the first one of that kind, saved to LOOK_OUT.
	var look := OS.get_environment("LOOK")
	if look != "":
		var target: Node3D = null
		for act in _find(root, "BeachActivity"):
			for w: Dictionary in act.get("_water"):
				if target == null and String(w.kind) == look:
					target = w.node
		if target:
			var cam := Camera3D.new()
			current_scene.add_child(cam)
			var at := target.global_position
			cam.global_position = at + Vector3(6.0, 2.2, 3.0)
			cam.look_at(at + Vector3(0.0, 0.6, 0.0))
			cam.current = true
			for i in 20:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(OS.get_environment("LOOK_OUT") if OS.get_environment("LOOK_OUT") != "" else "build/rc_beach/look.png")
			print("LOOK saved at ", at)
	var traffic := current_scene.get_node_or_null("Traffic")
	var plan = current_scene.get("plan")
	var ws := root.get_node("/root/WorldState")
	var sr: GDScript = load("res://scripts/npc/sand_roads.gd")
	for node in get_nodes_in_group("vehicle"):
		var car := node as Node3D
		var wp: Vector3 = ws.call("to_world", car.global_position)
		if wp.x > -400.0 or absf(wp.z - 800.0) > 400.0:
			continue
		var t: Dictionary = car.get("traffic") if car.get("traffic") != null else {}
		var sand := false
		if t.has("axis"):
			sand = sr.call("on_sand", plan, int(t.axis), int(t.index), float(t.get("along", 0.0)))
		print("CAR %s at=%.1f,%.1f zone=%d traffic=%s sand=%s parent=%s" % [car.name, wp.x, wp.z, plan.zone_at(Vector2(wp.x, wp.z)), str(t.get("axis", "-")) + ":" + str(t.get("index", "-")), sand, car.get_parent().name])
	quit()


func _find(n: Node, nm: String) -> Array:
	var out: Array = []
	if n.name == nm:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, nm))
	return out
