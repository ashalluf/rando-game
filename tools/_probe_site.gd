extends SceneTree
func _initialize() -> void:
	var plan := CityPlan.new()
	plan.seed = 20240917
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	for p: Vector2 in [Vector2(-900, -430), Vector2(-949, -340), Vector2(-885, -430), Vector2(-915, -430), Vector2(-900, -415), Vector2(-900, -445)]:
		print("at %v zone=%d district=%d h=%.2f" % [p, plan.zone_at(p), plan.district_at(p), plan.height_at(p)])
	var bi := plan.block_index_at(Vector2(-900, -430))
	print("block_index=%v block=%s" % [bi, plan.block(bi.x, bi.y)])
	quit()
