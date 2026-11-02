extends Node
## The front-yard ground kinds YardFill plans on the suburb blocks round a point (pure, seconds):
##   godot --headless --path . tools/rc2_suburb/yard_probe.tscn -- --spawn=x,z [R=metres]
func _ready() -> void:
	var c := Vector2(1990, 4260)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 120.0
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var plan = gc.call("make_plan", 1337)
	var lo: Vector2i = plan.block_index_at(c - Vector2(reach, reach))
	var hi: Vector2i = plan.block_index_at(c + Vector2(reach, reach))
	var totals := {}
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			var d := int(b.district)
			if d != CityPlan.District.SUBURBS or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			var lots: Array = plan.lots(bx, bz)
			lots.append_array(HouseKit.extra_lots(plan, bx, bz))
			var entries: Array = []
			for lot: Dictionary in lots:
				if lot.yard or YardFill.is_corridor(plan, lot):
					continue
				var house := HouseKit.plan_house(plan, bx, bz, lot, d)
				entries.append(HouseKit.yard_entry(lot, house))
			var bp := YardFill.beach_block(plan, bx, bz, entries)
			for lp: Dictionary in bp.lots:
				var line := ""
				for pc: Array in lp.pieces:
					if String(pc[3]) == "front":
						var k: String = YardFill.G_NAMES[int(pc[1])]
						totals[k] = int(totals.get(k, 0)) + 1
						line += "%s(%.0f,%.0f %.0fx%.0f) " % [k, (pc[0] as Rect2).position.x, (pc[0] as Rect2).position.y, (pc[0] as Rect2).size.x, (pc[0] as Rect2).size.y]
				print("BLOCK %d,%d lot %s: %s" % [bx, bz, str((lp.cell as Rect2).get_center().round()), line])
	print("FRONT KINDS ", totals)
	get_tree().quit()
