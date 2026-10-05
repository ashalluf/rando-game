extends SceneTree
## Lists the streamed chunks that built beach life round a --spawn (level, block, z range, figures,
## riders, walkers): headless, for finding why a stretch is empty.
##   godot --headless --path . --script tools/beach/chunks.gd -- --noload --spawn=x,z,0,0 --hour=15
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 60:
		await process_frame
	for c in current_scene.get_children():
		if not c.has_method("owned_rect"):
			continue
		var r: Rect2 = c.owned_rect()
		var figs := 0
		var other := 0
		for n in c.get_children():
			if n.get_class() == "StaticBody3D" and String(n.name).begins_with("BeachFigure"):
				figs += 1
			if String(n.name).begins_with("Rider") or n.get_script() and String(n.get_script().resource_path).ends_with("beach_walker.gd"):
				other += 1
		var dots := c.find_child("Batch_beach_dot_towel", false, false) != null
		if c.has_meta("beach_plan") or dots:
			print("CHUNK %d,%d level=%d z=%.0f..%.0f x=%.0f..%.0f planned=%d figures=%d movers=%d dots=%s" % [c.ix, c.iz, c.level, r.position.y, r.end.y, r.position.x, r.end.x,
				(c.get_meta("beach_plan").people as Array).size() if c.has_meta("beach_plan") else -1, figs, other, str(dots)])
	quit()
