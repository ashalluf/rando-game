extends SceneTree
func _initialize() -> void:
	var plan := CityPlan.new()
	plan.setup(1337)
	for p: Vector2 in [Vector2(-900, -430), Vector2(-949, -340), Vector2(-880, -430), Vector2(-920, -430), Vector2(-900, -410), Vector2(-900, -450)]:
		print("at %v zone=%d district=%d h=%.2f" % [p, plan.zone_at(p), plan.district_at(p), plan.height_at(p)])
	var a := Vector2(-900, -430)
	var bi := plan.block_index_at(a)
	print("block_index=%v" % bi)
	var b: Dictionary = plan.block(bi.x, bi.y)
	print("block rect=%s" % [b.get("rect", b)])
	quit()
