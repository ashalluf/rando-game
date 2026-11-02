extends SceneTree
## Where the yard's surface really is at a few apron points (a ray down on the world layer) against
## the plan's relief and the port chunk's lift: PortNight lays its apron pools on it.
##   godot --headless --path . --script tools/rc4_port_night/ground_probe.gd -- --spawn=3182,6490,101,10
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 40:
		await physics_frame
	var city := current_scene
	var plan = city.get("plan")
	var ws = root.get_node("/root/WorldState")
	var space := (city as Node3D).get_world_3d().direct_space_state
	for p: Vector2 in [Vector2(3182, 6490), Vector2(3178, 6484), Vector2(3154, 6465), Vector2(3100, 6470), Vector2(3125, 6440), Vector2(3060, 6300)]:
		var top: Vector3 = ws.call("to_local", Vector3(p.x, 50.0, p.y))
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -80, 0), 1)
		var hit := space.intersect_ray(q)
		var y := -999.0
		if hit:
			y = (ws.call("to_world", hit.position) as Vector3).y
		var ix: Vector2i = plan.block_index_at(p)
		var c: Vector2 = plan.owned_rect(ix.x, ix.y).get_center()
		print("GROUND %s ray %.2f relief %.2f height_at %.2f centre relief %.2f collider %s" % [str(p), y, plan.macro.relief_at(p), plan.height_at(p), plan.macro.relief_at(c), str(hit.get("collider")) if hit else "-"])
	quit()
