extends SceneTree
## Where the downtown crowds stand (rc2-crowd-plaza): every civic site's crowd rect in true world
## metres, with its count, so a camera can be framed on the busiest. Headless, seconds.
##   godot --headless --path . --script tools/crowd_plaza_probe.gd

func _initialize() -> void:
	await process_frame
	var m := MacroMap.new()
	m.seed = 1337
	m.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = m
	for lm in Landmarks.all():
		var cr: Array = Landmarks.crowds(lm, plan)
		for c: Array in cr:
			var r: Rect2 = c[0]
			var g := r.get_center()
			print("CROWD %-20s count %3d rect %s centre (%.1f, %.1f) ground %.2f" % [lm.id, int(c[2]), str(r), g.x, g.y, plan.height_at(g)])
	quit()
