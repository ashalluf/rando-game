extends SceneTree
## The drop-off at the terminal: the blocks just north of it, the people and loop cars there.
##   godot --headless --path . --script tools/terminal_curb/probe.gd -- --spawn=-404,627,0,0 --hour=8
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 240:
		await physics_frame
	var plan = current_scene.get("plan")
	for ix in range(-12, 12):
		for iz in range(-4, 12):
			var b: Dictionary = plan.block(ix, iz)
			var r: Rect2 = b.rect
			if r.end.x < -520 or r.position.x > -180 or r.end.y < 520 or r.position.y > 600:
				continue
			print("BLOCK %d,%d rect %s kind %s zone %s" % [ix, iz, r, b.get("kind"), plan.zone_at(r.get_center())])
	var n := 0
	for p in root.get_tree().get_nodes_in_group("pedestrian"):
		var w: Vector3 = root.get_node("/root/WorldState").to_world(p.global_position)
		if w.x > -500 and w.x < -200 and w.z > 590 and w.z < 640:
			n += 1
			print("PED %s %s" % [p.get_class(), w])
	print("PEDS near curb ", n)
	var tm = current_scene.find_child("Traffic", true, false)
	if tm:
		print("LOOP CARS ", tm.get("loop_cars").size())
	quit()
