extends "res://tools/glshot/still_shot.gd"
## Which node draws that? Every still_shot.gd shot is saved again once per name pattern with every
## GeometryInstance3D whose own name (or a parent's, up to the chunk) matches it hidden:
## <shot>_hide_<i>.png. Run like still_shot.gd with TREES_AB=1 (the per-shot hook) and
## HIDE_PATTERNS="*Deck*;*Traffic*;group:vehicle" (';' between patterns; "group:<g>" hides a group's
## nodes and everything under them). The night aerial review used it to pin the freeway's glow.


func _trees_ab(path: String) -> void:
	var pats := OS.get_environment("HIDE_PATTERNS").split(";", false)
	for i in pats.size():
		var pat := String(pats[i])
		var hidden: Array = []
		if pat.begins_with("group:"):
			for n in get_nodes_in_group(pat.substr(6)):
				if n is Node3D and (n as Node3D).visible:
					(n as Node3D).visible = false
					hidden.append(n)
		else:
			for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
				var gi := n as GeometryInstance3D
				if not gi.visible:
					continue
				var p: Node = gi
				var hit := false
				for k in 3:
					if p == null or p == current_scene:
						break
					if String(p.name).match(pat):
						hit = true
						break
					p = p.get_parent()
				if hit:
					gi.visible = false
					hidden.append(gi)
		print("HIDE %d %s: %d nodes" % [i, pat, hidden.size()])
		for k in 3:
			await process_frame
		get_root().get_texture().get_image().save_png(path.get_basename() + "_hide_%d.png" % i)
		for n in hidden:
			if is_instance_valid(n):
				(n as Node3D).visible = true
	for k in 2:
		await process_frame
