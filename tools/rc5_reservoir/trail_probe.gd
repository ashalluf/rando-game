extends Node
## The lake trail's points with the dam and the towers, to frame the reservoir_dam refcam (headless,
## seconds): godot --headless --path . res://tools/rc5_reservoir/trail_probe.tscn

func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var res: Reservoir = macro.reservoir
	print("LEVEL %.1f crest %.1f toe %.1f centre %s a0 %.3f a1 %.3f lake %s" % [res.level, res.crest, res.toe, res.dam_centre, res.dam_a0, res.dam_a1, res.lake_centre()])
	print("DAM mid %s" % res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS))
	for li in res.trail.size():
		var line: PackedVector2Array = res.trail[li]
		for k in range(0, line.size(), 6):
			var p := line[k]
			var d := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS) - p
			print("T%d %d %.1f %.1f h %.1f dam %.0f m yaw %.1f" % [li, k, p.x, p.y, macro.height_at(p), d.length(), rad_to_deg(atan2(-d.x, -d.y))])
	var o := Rc5Reservoir.overlook(res)
	if not o.is_empty():
		var c: Vector2 = o.centre
		var eye := c + (o.out as Vector2) * 1.2
		var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
		var d := mid - eye
		print("OVERLOOK at %s out %s centre %s EYE %.1f,%.2f,%.1f yaw %.1f dam %.0f m ground %.2f" % [o.at, o.out, c, eye.x, res.level + Reservoir.TRAIL_RISE + 0.07 + 1.65, eye.y, rad_to_deg(atan2(-d.x, -d.y)), d.length(), macro.height_at(eye)])
	get_tree().quit()
