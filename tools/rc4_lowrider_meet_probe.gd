extends SceneTree
## rc4-lowrider-meet: loads the city at the meet and prints each row car's hydraulics (routine,
## heights) and place, headless.
##   LOWRIDER_MEET=1 LOWRIDER_POSE=... godot --headless --path . --script tools/rc4_lowrider_meet_probe.gd -- --spawn=826,597,0,0 --hour=19.5
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 240:
		await process_frame
	for car in get_nodes_in_group("lowrider_meet"):
		var h: Node = car.get_node_or_null("Hydraulics")
		var p: Vector3 = get_root().get_node("WorldState").call("to_world", car.global_position)
		print("LRCAR %s at %.1f,%.1f,%.1f type %d routine '%s' lights %s h %s frozen %s body %s" % [car.name, p.x, p.y, p.z, car.body_type,
			h.call("routine") if h else "-", car.call("lights_running"), h.call("heights") if h else "-", h.get("frozen") if h else "-", car.get_node_or_null("BodyModel") != null])
	for ped in get_nodes_in_group("pedestrian"):
		if ped.get_script() != null and ped.get_script().get_global_name() == &"MeetGoer":
			var q: Vector3 = get_root().get_node("WorldState").call("to_world", ped.global_position)
			print("LRGOER at %.1f,%.1f act %d sitter %s" % [q.x, q.z, int(ped.get("_act")), ped.get("sitter")])
	quit()
