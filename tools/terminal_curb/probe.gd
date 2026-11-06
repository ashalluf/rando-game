extends SceneTree
## The drop-off at the terminal: the travellers (CurbTraveller), the crowd and props on the kerb,
## the loop cars and their kerb stops.
##   godot --headless --path . --script tools/terminal_curb/probe.gd -- --spawn=-404,627,0,0 --hour=8
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 300:
		await physics_frame
	var ws = root.get_node("/root/WorldState")
	var trav := 0
	var other := 0
	for p in root.get_tree().get_nodes_in_group("pedestrian"):
		var w: Vector3 = ws.to_world(p.global_position)
		if w.x > -500 and w.x < -200 and w.z > 622 and w.z < 640:
			if p.get_script() and String(p.get_script().resource_path).ends_with("curb_traveller.gd"):
				trav += 1
			else:
				other += 1
	print("TRAVELLERS ", trav, " OTHER ", other, " total peds ", root.get_tree().get_nodes_in_group("pedestrian").size())
	# Anything near the odd box on the kerb at (-402, 624.5).
	for n in root.find_children("*", "Node3D", true, false):
		var w: Vector3 = ws.to_world((n as Node3D).global_position)
		if Vector2(w.x, w.z).distance_to(Vector2(-401.5, 624.3)) < 2.5 and w.y < 3.0:
			print("NEAR ", n.get_path(), " ", n.get_class(), " ", w)
	var tm = current_scene.find_child("Traffic", true, false)
	if tm:
		var stopped := 0
		for c in tm.get("loop_cars"):
			if c.traffic.get("hazard", false):
				stopped += 1
		print("LOOP CARS ", tm.get("loop_cars").size(), " stopped ", stopped)
	quit()
