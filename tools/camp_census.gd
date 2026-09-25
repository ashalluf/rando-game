extends SceneTree
## Counts the encampments the streamed city actually built round a spot: per detailed chunk, the
## camp batch instances (every tent, cart, bag...), the knockable pieces, the people at the camps
## (rigged) and the posed figures, with the block's district and skid-row value. Headless is fine:
## MultiMesh instance counts are real there, only their transforms are not.
##
##   godot --headless --path . --script tools/camp_census.gd -- --spawn=950,300,0,-10,3 --noload
##
## Env: FRAMES (default 400) frames to let the chunks build.
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 400
	for i in frames:
		await process_frame
	var city := current_scene
	var enc: GDScript = load("res://scripts/world/encampment.gd")
	var plan = city.get("plan")
	var totals := {"chunks": 0, "camp_chunks": 0, "pieces": 0, "items": 0, "people": 0, "figures": 0, "tents": 0, "downtown_blocks": 0}
	var keys: Array = city.chunks.keys()
	keys.sort()
	for k: Vector2i in keys:
		var c: Node3D = city.chunks[k]
		if int(c.get("level")) != 0:
			continue
		totals.chunks += 1
		var pieces := 0
		var tents := 0
		var figures := 0
		var items := 0
		var people := 0
		var kinds := 0
		for child in c.get_children():
			if child is MultiMeshInstance3D:
				var n := str(child.name)
				var count := (child as MultiMeshInstance3D).multimesh.instance_count
				if n.begins_with("Batch_camp_"):
					pieces += count
					kinds += 1
					if n.contains("tent") or n.contains("tarp"):
						tents += count
				elif n.begins_with("Batch_campfig_"):
					figures += count
					kinds += 1
			elif child.get_script() and str(child.get_script().get_global_name()) == "EncampmentItem":
				items += 1
			elif child.get_script() and str(child.get_script().get_global_name()) == "RoughSleeper":
				people += 1
		var block: Dictionary = plan.block(k.x, k.y)
		if int(block.district) == 0 and int(block.kind) == 0:
			totals.downtown_blocks += 1
		if pieces + people + figures > 0:
			totals.camp_chunks += 1
			print("chunk %s rect %s district %d skid %.2f: pieces %d (tents/tarps %d), bodies %d, people %d, figures %d, batch kinds %d" % [
				str(k), str(block.rect), int(block.district), (float(enc.skid_row(plan, k.x, k.y)) if enc.source_code.contains("func skid_row") else 0.0), pieces, tents, items, people, figures, kinds])
		totals.pieces += pieces
		totals.tents += tents
		totals.items += items
		totals.people += people
		totals.figures += figures
	print("CENSUS ", totals, " pedestrians in group: ", get_nodes_in_group("pedestrian").size())
	quit()
