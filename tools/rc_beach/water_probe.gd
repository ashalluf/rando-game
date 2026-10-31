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
	quit()


func _find(n: Node, nm: String) -> Array:
	var out: Array = []
	if n.name == nm:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, nm))
	return out
