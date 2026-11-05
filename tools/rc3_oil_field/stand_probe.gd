extends Node
## Prints OilFieldPlanting's stand field and keep-outs on a grid round a point (ASCII), seconds:
##   godot --headless --path . res://tools/rc3_oil_field/stand_probe.tscn   (AT=x,z)
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var f: OilField = macro.oil
	var at := Vector2(611.4, 1542.8)
	if OS.get_environment("AT") != "":
		var a := OS.get_environment("AT").split(",")
		at = Vector2(float(a[0]), float(a[1]))
	for q: Vector2 in [at + Vector2(0.835, -0.551) * 25.0 + Vector2(0.551, 0.835) * 10.0, at + Vector2(0.835, -0.551) * 40.0 + Vector2(0.551, 0.835) * 15.0, at + Vector2(0.835, -0.551) * 20.0 - Vector2(0.551, 0.835) * 12.0]:
		print("at %s clear %s fence %.1f stand %.2f drain %.2f" % [q, OilFieldPlanting.clear(f, q), OilFieldPlanting.fence_in(f, q), OilFieldPlanting.stand(f, q), f.drainage(q)])
	var n_st := 0
	var n_room := 0
	var n := 0
	for j in range(-20, 21):
		var line := ""
		for i in range(-30, 31):
			var p := at + Vector2(i * 4.0, j * 4.0)
			var s := OilFieldPlanting.stand(f, p)
			var r := OilFieldPlanting.room(f, p, 0.0)
			n += 1
			if r:
				n_room += 1
				if s > 0.5:
					n_st += 1
			line += ("#" if s > 0.5 else ("+" if s > 0.35 else ".")) if r else " "
		print(line)
	print("room %d of %d, stand in room %d" % [n_room, n, n_st])
	get_tree().quit()
