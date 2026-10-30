extends Node
## Lists the corner stores (CornerStore.plan_for()) round a point for a seed: block, district,
## size, name, which corner, and two EYEs for tools/glshot/still_shot.gd - across the front street
## looking at the storefront, and inside by the door looking in. Then builds the nearest one alone
## (no chunk) and prints its triangles and goods. Headless, seconds.
##   godot --headless --path . tools/walk_in_store/probe.tscn [-- --seed=N --at=x,z --radius=m --district=n]

func _ready() -> void:
	await get_tree().process_frame
	var seed_value := 1337
	var at := Vector2(0.0, 0.0)
	var radius := 2500.0
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
		elif a.begins_with("--district="):
			only = int(a.substr(11))
		elif a.begins_with("--radius="):
			radius = float(a.substr(9))
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.macro = m
	var t0 := Time.get_ticks_msec()
	var all := CornerStore.near(plan, at, radius)
	print("CSTORE %d stores within %.0f m of %s (%d ms)" % [all.size(), radius, at, Time.get_ticks_msec() - t0])
	var by := {}
	for s: Dictionary in all:
		by[int(s.district)] = int(by.get(int(s.district), 0)) + 1
	print("CSTORE by district %s; corners refused: %s" % [by, CornerStore.reasons])
	if only >= 0:
		all = all.filter(func(x: Dictionary) -> bool: return int(x.district) == only)
	for i in mini(all.size(), 24):
		var s: Dictionary = all[i]
		var o: Vector2 = s.origin
		var f: Vector2 = s.front
		var sd: Vector2 = s.side
		var y := m.relief_at(o) + CityChunk.SIDEWALK_TOP
		var out := o + f * 14.0 - sd * 4.0
		var look := (o - out).normalized()
		var yaw := rad_to_deg(atan2(-look.x, -look.y))
		var inside := o - f * 0.9 - sd * float(s.W) * 0.3
		var yaw_in := rad_to_deg(atan2(f.x, f.y))
		print("STORE %-24s blk %s d%d %.1fx%.1f corner %s front %s  EYE=%.1f,%.1f,%.1f,%.0f,4  IN=%.1f,%.1f,%.1f,%.0f,-8" % [
			s.name, str(s.block), int(s.district), float(s.W), float(s.D), str(s.corner), str(f),
			out.x, y + 1.7, out.y, yaw, inside.x, y + 1.65, inside.y, yaw_in])
	get_tree().quit()
