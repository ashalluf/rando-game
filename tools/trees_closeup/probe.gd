extends SceneTree
## Finds palm-lined and jacaranda streets and street-tree blocks round a point, for framing stills
## of the street trees close up (trees-closeup):
##   godot --headless --path . --script tools/trees_closeup/probe.gd -- --spawn=x,z,0,0
## R=blocks (default 3). Each FULL chunk is built and its tree batches counted; a line per block
## with palms, jacarandas or broadleaf trees gives an EYE for still_shot.gd on the pavement at
## the block's +Z kerb, looking along it.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var reach := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 3
	var start: Vector2i = plan.block_index_at(c)
	for ix in range(start.x - reach, start.x + reach + 1):
		for iz in range(start.y - reach, start.y + reach + 1):
			var chunk = city.call("_new_chunk", Vector2i(ix, iz), 0)
			chunk.call("build")
			var counts := {}
			for n: Node in chunk.find_children("Batch_*", "", true, false):
				var key := String(n.name).trim_prefix("Batch_")
				if key.begins_with("tree_") or key.begins_with("palm_"):
					var mmi := n as MultiMeshInstance3D
					if mmi and mmi.multimesh:
						counts[key] = int(counts.get(key, 0)) + mmi.multimesh.instance_count
			if not counts.is_empty():
				var r: Rect2 = plan.block(ix, iz).rect
				var eye := Vector2(r.position.x + 6.0, r.end.y - 2.0)
				var palm := bool(chunk.get("_palm_street"))
				var jac := bool(chunk.get("_jacaranda_street"))
				print("TREES block=%d,%d district=%d palm_street=%s jac_street=%s %s EYE=%.1f,1.7,%.1f,-90,4" % [ix, iz,
					plan.district_at(r.get_center()), palm, jac, counts, eye.x, eye.y])
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	quit()
