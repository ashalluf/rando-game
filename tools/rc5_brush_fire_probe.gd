extends SceneTree
## rc5-brush-fire: prints the fire site and the north-south roads round a midtown spot with their
## districts, to frame the brush_fire refcam:
##   godot --headless --path . --script tools/rc5_brush_fire_probe.gd
func _initialize() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	root.add_child(city)
	await process_frame
	var plan: Variant = city.get("plan")
	var fire := LaWeather.fire_site(plan)
	print("FIRE ", fire)
	for z in range(1200, -200, -100):
		var row := "z %5d:" % z
		for x in range(-700, 1300, 100):
			var d: Variant = plan.district_at(Vector2(x, z))
			row += " %d" % int(d)
		print(row)
	# Roads near x = fire.x (axis 0 = roads at fixed x?)
	for axis in [0, 1]:
		var i0: int = plan.block_index_at(Vector2(fire.x, 400.0)).x if axis == 0 else plan.block_index_at(Vector2(fire.x, 400.0)).y
		for i in range(i0 - 4, i0 + 5):
			print("ROAD axis ", axis, " i ", i, " pos ", plan.road_pos(axis, i), " w ", plan.road_width(axis, i), " name ", plan.road_name(axis, i))
	quit()
