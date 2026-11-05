extends Node
## A top-down map (1 m a pixel) of OilFieldPlanting's ground round a point: road grey, pad brown,
## a stand green, open room yellow, a keep-out red; the eye white with its view line.
##   OUT=/tmp/m.png AT=x,z YAW=deg godot --headless --path . res://tools/rc3_oil_field/map_probe.tscn
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var f: OilField = macro.oil
	var at := Vector2(611.4, 1542.8)
	if OS.get_environment("AT") != "":
		var a := OS.get_environment("AT").split(",")
		at = Vector2(float(a[0]), float(a[1]))
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else -56.6)
	var r := 160
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGB8)
	for j in r * 2:
		for i in r * 2:
			var p := at + Vector2(i - r, j - r)
			var c := OilFieldPlanting.clear(f, p)
			var col := Color(0.8, 0.2, 0.2)
			if c.x < 0.0:
				col = Color(0.5, 0.5, 0.5)
			elif c.y < 0.0:
				col = Color(0.5, 0.35, 0.2)
			elif OilFieldPlanting.room(f, p, 0.0):
				col = Color(0.2, 0.6, 0.2) if OilFieldPlanting.stand(f, p) > OilFieldPlanting.STAND_MIN else Color(0.85, 0.8, 0.4)
			img.set_pixel(i, j, col)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	for k in 150:
		var q := Vector2(r, r) + fwd * k
		img.set_pixel(int(q.x), int(q.y), Color.WHITE)
	img.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/oil_map.png")
	get_tree().quit()
