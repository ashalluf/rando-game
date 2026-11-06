extends Node
## Finds the sea_of_clouds eye: hill-road points over MIN_H (default 420 m) with the ground they
## look down on to the south-west, and the highest ground in REGION. Headless, a minute:
##   godot --headless --path . res://tools/rc5_sea_of_clouds/probe.tscn
## (A scene, not --script: under --script the autoloads are missing and the hills come out
## different.)

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	macro.setup()
	city.free()
	var min_h := float(OS.get_environment("MIN_H")) if OS.get_environment("MIN_H") != "" else 420.0
	var best := {}
	for road in macro.hill_roads.roads:
		var pts: PackedVector2Array = road.points
		for i in range(0, pts.size(), 2):
			var h: float = macro.height_at(pts[i])
			if h < min_h:
				continue
			var key := Vector2i(int(pts[i].x / 500.0), int(pts[i].y / 500.0))
			if best.has(key) and best[key][1] >= h:
				continue
			var s := ""
			for d in [600.0, 1500.0, 3000.0]:
				s += " %.0f" % macro.height_at(pts[i] + Vector2(-0.6, 0.8) * d)
			best[key] = [pts[i], h, road.name, s]
	for k in best:
		var b: Array = best[k]
		print("ROAD %s at %.0f,%.0f ground %.0f | SW 0.6/1.5/3 km:%s" % [b[2], b[0].x, b[0].y, b[1], b[3]])
	for q in OS.get_environment("PROBE").split(";", false):
		var xy := q.split(",")
		var pp := Vector2(xy[0].to_float(), xy[1].to_float())
		print("PROBE %s height %.1f" % [pp, macro.height_at(pp)])
	get_tree().quit()
