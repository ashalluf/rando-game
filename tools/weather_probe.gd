extends SceneTree
## Prints the front range's heights north of downtown and the brush fire's site (LaWeather), for
## framing the LA weather stills:
##   godot --headless --path . --script tools/weather_probe.gd
func _initialize() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	root.add_child(city)
	await process_frame
	var plan: Variant = city.get("plan")
	for z in range(-1000, -4600, -300):
		var row := "z %5d:" % z
		for x in range(-400, 3600, 400):
			row += " %4d" % int(plan.macro.height_at(Vector2(x, z)))
		print(row)
	print("FIRE ", LaWeather.fire_site(plan), " coast_base_x ", plan.macro.coast_base_x)
	# FULL chunks round the spawn whose street trees are palms (a Santa Ana still wants one).
	for key in city.get("chunks"):
		var ch: Variant = city.get("chunks")[key]
		if ch and ch.get("_palm_street") and ch.get("level") == 0:
			var b: Dictionary = plan.block(key.x, key.y)
			print("PALMS block ", key, " rect ", b.rect, " district ", str(b.district))
	quit()
