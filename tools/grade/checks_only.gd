extends Node
## Runs tests/color_grade_checks.gd (and photo mode's, which shares the look LUT) alone against
## the city scene, a minute or two instead of the whole smoke test:
##   godot --headless --path . res://tools/grade/checks_only.tscn   (TWO_CITIES=1: a city first,
##   HOUR=h: the clock there first)

var fails := 0


func _ready() -> void:
	await get_tree().process_frame
	# TWO_CITIES=1: a city loaded and freed first, as the smoke test does (the Environment is shared).
	if OS.get_environment("TWO_CITIES") == "1":
		var first: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(first)
		for i in 10:
			await get_tree().process_frame
		first.queue_free()
		await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	get_tree().root.add_child(city)
	# HOUR=h: the clock there first (where the looks blend, every frame moves the grade).
	if OS.get_environment("HOUR") != "":
		city.get_node("DayNight").set("hour", OS.get_environment("HOUR").to_float())
	for i in 30:
		await get_tree().process_frame
	await load("res://tests/photo_mode_checks.gd").new().run(self, city)
	for i in 5:
		await get_tree().process_frame
	load("res://tests/color_grade_checks.gd").new().run(self, city)
	print("CHECKS_ONLY failures=%d" % fails)
	get_tree().quit()


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
