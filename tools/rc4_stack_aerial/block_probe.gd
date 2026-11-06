extends Node
## The blocks under and round the four-level stack: kind, district, lots, how many are the
## freeway's right of way, and RcStack's planting spots in it. Headless, seconds:
##   godot --headless --path . res://tools/rc4_stack_aerial/block_probe.tscn   (AT=x,z RADIUS=m)
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var at := Vector2(2133.6, -1385.1)
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		at = Vector2(float(p[0]), float(p[1]))
	var radius := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 350.0
	var c := plan.block_index_at(at)
	for bx in range(c.x - 3, c.x + 4):
		for bz in range(c.y - 3, c.y + 4):
			var b: Dictionary = plan.block(bx, bz)
			var r: Rect2 = b.rect
			if r.get_center().distance_to(at) > radius:
				continue
			var lots := plan.lots(bx, bz)
			var under := 0
			for lot: Dictionary in lots:
				var size: Vector2 = lot.size
				if macro.freeway.blocks_rect(Rect2((lot.center as Vector2) - size * 0.5, size), 4.0):
					under += 1
			var sp := RcStack.spots(plan, bx, bz)
			var nt := 0
			for q: Array in sp:
				if int(q[1]) == 0:
					nt += 1
			print("  rc4 spots %d trees %d shrubs %d" % [sp.size(), nt, sp.size() - nt])
			print("block %d,%d rect %s kind %d district %d lots %d corridor %d keys %s" % [bx, bz, r, int(b.kind), int(b.district), lots.size(), under, b.keys()])
	get_tree().quit()
