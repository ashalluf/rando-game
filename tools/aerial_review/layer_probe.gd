extends "res://tools/glshot/still_shot.gd"
## Which layer is that? Every still_shot.gd shot (main and SHOTS) is saved again once per layer
## with that layer hidden (<shot>_hide_<layer>.png), so a speckle or a seam in an aerial can be
## pinned on the node that draws it. A layer is the scene root's child the geometry is under
## (CityChunk children split further by still_shot's own categories). Run like still_shot.gd with
## TREES_AB=1 (the per-shot hook) and LAYERS=a,b,c to limit it (default: every layer).


func _trees_ab(path: String) -> void:
	var groups := {}
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var top: Node = gi
		while top.get_parent() != current_scene and top.get_parent() != null:
			top = top.get_parent()
		var key := String(top.name)
		if (top.get_script() and String(top.get_script().get_global_name()) == "CityChunk") or String(top.name).begins_with("Chunk"):
			key = "chunk_" + _split_category(gi)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(gi)
	var only := OS.get_environment("LAYERS")
	print("LAYERS ", groups.keys())
	for key: String in groups.keys():
		if only != "" and not only.split(",").has(key):
			continue
		for gi in groups[key]:
			if is_instance_valid(gi):
				(gi as GeometryInstance3D).visible = false
		for i in 3:
			await process_frame
		get_root().get_texture().get_image().save_png(path.get_basename() + "_hide_%s.png" % key.validate_filename())
		for gi in groups[key]:
			if is_instance_valid(gi):
				(gi as GeometryInstance3D).visible = true
	for i in 2:
		await process_frame
