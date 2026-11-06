extends Node
## CPU cost of the birds (Birds): 12 flocks of 25 pigeons staged round the player, then 200
## frames of the simulation alone and of the buffer writes alone, on the ground and in the air.
##   godot --headless --path . res://tools/bird_bench.tscn
func _ready():
	var city = load("res://scenes/levels/city.tscn").instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 20:
		await get_tree().process_frame
	var birds = city.get_node("Birds")
	var player = get_tree().get_first_node_in_group("player")
	var p = player.global_position
	var staged := 0
	for k in 12:
		var q = p + Vector3(cos(k) * (8 + k * 4), 0, sin(k) * (8 + k * 4))
		var space = city.get_world_3d().direct_space_state
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 30, q - Vector3.UP * 30, 1))
		if hit.is_empty(): continue
		if birds.call("stage", "pigeon", hit.position, 25, 4.0) != 0: staged += 25
	birds.shot_calm = true
	print("BENCH birds ", birds.call("bird_count"), " flocks ", birds.call("flock_count"))
	for mode in ["ground", "air"]:
		if mode == "air":
			for f in birds.flocks_info(): birds.flush_flock(f.id, p)
		var t0 = Time.get_ticks_usec()
		t0 = Time.get_ticks_usec()
		for i in 200:
			birds._draw()
		print("BENCH " + mode + " draw %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0))
		t0 = Time.get_ticks_usec()
		var eye = birds._player_local()
		for i in 200:
			for f in birds._flocks.values():
				birds._tick_flock(f, 1.0/60.0, eye)
		print("BENCH " + mode + " simulate %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0))
	get_tree().quit()
