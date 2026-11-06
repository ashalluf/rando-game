extends SceneTree
## The yard's chunks built FULL headless (rc4-freight-yard): per chunk its owned rect and what the
## freight kit laid (ties, timbers, cars) with their bounds. A few minutes:
##   godot --headless --path . --script tools/rc4_freight_yard/chunk_probe.gd
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 10:
		await process_frame
	var city: Node3D = current_scene
	var plan = city.get("plan")
	var line = load("res://scripts/world/freight_rail.gd").of(plan)
	var keys := {}
	var y: Rect2 = line.yard_rect
	var x := y.position.x + 2.0
	while x < y.end.x:
		var z := y.position.y + 2.0
		while z < y.end.y:
			keys[plan.chunk_index_at(Vector2(x, z))] = true
			z += 20.0
		x += 20.0
	for k in keys:
		var c = city.call("_new_chunk", k, 0)
		c.build()
		print("chunk %s owned %s" % [k, c.owned_rect()])
		for n in c.get_children():
			if n is MultiMeshInstance3D and (str(n.name).begins_with("Freight") or str(n.name).begins_with("Batch_fr")):
				var mm: MultiMesh = n.multimesh
				print("  %s n=%d aabb=%s vis_end=%.0f" % [n.name, mm.instance_count, n.get_aabb(), n.visibility_range_end])
		c.get_parent().remove_child(c)
		c.free()
	quit()
