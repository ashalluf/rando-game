extends SceneTree
func _initialize() -> void:
	var plan := CityPlan.new()
	plan.macro = MacroMap.new()
	plan.macro.setup(12345)
	await process_frame
	for spot: Array in [["manhattan", Vector2(-690.0, 1100.0)], ["redondo", Vector2(-765.0, 1450.0)]]:
		var a: Vector2 = spot[1]
		print("--- ", spot[0], " anchor ", a)
		for dx: float in [-300.0, -200.0, -100.0, -20.0, 0.0, 10.0, 22.0, 40.0, 72.0, 120.0]:
			var q := a + Vector2(dx, 0.0)
			print("   x%+7.1f zone=%d h=%6.2f" % [dx, plan.macro.zone_at(q), plan.height_at(q)])
	quit()
