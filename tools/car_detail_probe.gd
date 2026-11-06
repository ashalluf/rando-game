extends SceneTree
## CarDetail's numbers for one car (headless, seconds): its plate, grime, wheel dust and the glass's
## windscreen dust; `--type=N`.
##   godot --headless --path . --script tools/car_detail_probe.gd -- --type=16

func _initialize() -> void:
	var type := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--type="):
			type = a.trim_prefix("--type=").to_int()
	await process_frame
	var vehicle_script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var detail: GDScript = load("res://scripts/vehicles/car_detail.gd")
	var car = vehicle_script.new()
	car.body_type = type
	root.add_child(car)
	await process_frame
	detail.near(car)
	detail.flush()
	var look: int = detail.look_of(car)
	print("PLATE ", detail.plate_text(look), " GRIME ", detail.grime_for(type, look))
	for m in detail.paint_materials(car):
		print("PAINT grime ", m.get_shader_parameter("grime"), " arch ", m.get_shader_parameter("grime_arch"), " frame ", m.get_shader_parameter("grime_frame"))
	var g = car.get("_glass_shared")
	print("GLASS ", g, " dust ", g.get_shader_parameter("screen_dust") if g else null)
	for warm in 2:
		_build(vehicle_script, type, warm)
	var mi = car.get_node_or_null("CarDetail")
	print("DETAIL ", mi, " tris ", mi.mesh.get_faces().size() / 3 if mi else 0)
	quit()


func _build(vehicle_script: GDScript, type: int, warm: int) -> void:
	var detail: GDScript = load("res://scripts/vehicles/car_detail.gd")
	var t0 := Time.get_ticks_usec()
	for i in 20:
		var c2 = vehicle_script.new()
		c2.body_type = type
		c2.look_seed = i * 7919 + warm * 13
		root.add_child(c2)
		detail.near(c2)
		detail.flush()
		c2.queue_free()
	print("BUILD 20 cars (pass %d) " % warm, (Time.get_ticks_usec() - t0) / 1000, " ms")
