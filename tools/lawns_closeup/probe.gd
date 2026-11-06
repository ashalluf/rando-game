extends SceneTree
## Lawns close up (LawnsCloseup) without a city: lists the blocks round a point whose ground is
## the lawn shader - suburban block lawns, city parks, pocket gardens - with the district and an
## EYE for tools/glshot/still_shot.gd on the parkway / lawn edge of each. Seconds, headless.
##
##   godot --headless --path . --script tools/lawns_closeup/probe.gd -- --spawn=x,z [R=metres]

func _initialize() -> void:
	var c := Vector2(0, 0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 1500.0
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var plan = gc.call("make_plan", 1337)
	var lo: Vector2i = plan.block_index_at(c - Vector2(reach, reach))
	var hi: Vector2i = plan.block_index_at(c + Vector2(reach, reach))
	var shown := {}
	for bx in range(lo.x, hi.x + 1, 2):
		for bz in range(lo.y, hi.y + 1, 2):
			var b: Dictionary = plan.block(bx, bz)
			var rect: Rect2 = b.rect
			if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY or b.has("site") or b.has("grounds"):
				continue
			var d := int(b.district)
			var kind := int(b.kind)
			var tag := ""
			if kind == CityPlan.BlockKind.PARK:
				tag = "park"
			elif kind == CityPlan.BlockKind.BUILDINGS and bool(CityPlan.DISTRICTS[d].get("lawn", false)):
				tag = "lawn_d%d" % d
			if tag == "" or int(shown.get(tag, 0)) >= 4:
				continue
			shown[tag] = int(shown.get(tag, 0)) + 1
			var e := Vector2(rect.position.x + rect.size.x * 0.4, rect.position.y)
			var gy: float = plan.height_at(e)
			print("%s block %d,%d rect %s  EYE=%.1f,%.1f,%.1f,%.0f,%.0f" % [tag, bx, bz, rect, e.x, gy + 1.7, e.y - 1.0, 200.0, -18.0])
	quit()
