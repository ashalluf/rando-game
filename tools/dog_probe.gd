extends SceneTree
## Finds dogs for stills: loads the city at a spawn, waits for the chunks round it, and lists every
## yard dog (YardDog) and dog walker's dog (CrowdDog) with its breed, its true-world point and an
## EYE for tools/glshot/still_shot.gd 6 m off looking at it.
##   godot --headless --path . --script tools/dog_probe.gd -- --spawn=x,z,0,0
## FIND=1 instead lists the centres of suburb and beach-town blocks within R metres (default 3000)
## of the spawn (where the yards are).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	if OS.get_environment("FIND") == "1":
		var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 3000.0
		var start: Vector2i = plan.block_index_at(c)
		var span := int(reach / 120.0)
		var n := 0
		var names: Array = (load("res://scripts/world/city_plan.gd") as GDScript).get_script_constant_map()["District"].keys()
		for ix in range(start.x - span, start.x + span + 1, 2):
			for iz in range(start.y - span, start.y + span + 1, 2):
				var b: Dictionary = plan.block(ix, iz)
				var d := int(b.district)
				if names[d] == "SUBURBS" or names[d] == "BEACHTOWN":
					var rc: Vector2 = (b.rect as Rect2).get_center()
					if rc.distance_to(c) < reach and n < 40 and int(plan.zone_at(rc)) == 0:
						print("BLOCK %s %d,%d centre %.0f,%.0f" % [names[d], ix, iz, rc.x, rc.y])
						n += 1
		quit()
		return
	var waits := int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 1500
	for i in waits:
		await process_frame
	var ws: Node = root.get_node("/root/WorldState")
	var pl: Node3D = root.get_tree().get_first_node_in_group("player")
	print("PROBE player at %s district %s, %d dogs, %d chunks" % [str(ws.call("to_world", pl.global_position)), str(plan.district_at(Vector2(pl.global_position.x, pl.global_position.z))), root.get_tree().get_nodes_in_group("dog").size(), (current_scene.get("chunks") as Dictionary).size()])
	if OS.get_environment("CHUNKS") == "1":
		for key in (current_scene.get("chunks") as Dictionary):
			var ch = current_scene.get("chunks")[key]
			var b: Dictionary = plan.block(key.x, key.y)
			if ch.get("level") == 0:
				print("CHUNK ", key, " lv ", ch.get("level"), " zone ", ch.get("zone"), " district ", b.district, " kind ", b.kind, " lots ", (ch.get("_yard_lots") as Array).size())
	for n in root.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		var path := sc.resource_path if sc else ""
		if path.ends_with("/yard_dog.gd") or path.ends_with("/crowd_dog.gd"):
			var d = n
			var w: Vector3 = ws.call("to_world", d.global_position)
			var fwd: Vector3 = -d.global_basis.z
			var eye := w + Vector3(fwd.x, 0.0, fwd.z).normalized() * 4.5 + Vector3(fwd.z, 0.0, -fwd.x).normalized() * 3.0 + Vector3.UP * 1.6
			var look := w - eye
			var yaw := rad_to_deg(atan2(-look.x, -look.z))
			var pitch := rad_to_deg(atan2(look.y + 0.3, Vector2(look.x, look.z).length()))
			print("%s %s %s at %.1f,%.1f,%.1f EYE=%.1f,%.1f,%.1f,%.0f,%.0f" % ["YARD" if path.ends_with("/yard_dog.gd") else "WALKER", d.breed, d.look, w.x, w.y, w.z, eye.x, eye.y, eye.z, yaw, pitch])
	quit()
