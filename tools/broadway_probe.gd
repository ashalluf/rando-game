extends SceneTree
## Lists Broadway's movie palaces for a seed (Broadway.palaces()): the address, where it landed,
## the lot, its frontage and an EYE for still_shot.gd looking at it from across the street.
##   godot --headless --path . --script tools/broadway_probe.gd [-- --seed=N]

func _initialize() -> void:
	await process_frame
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.macro = m
	var x := Broadway.avenue_x()
	print("BROADWAY x %.1f width %.1f z %s" % [x, Broadway.avenue_width(), Broadway.z_range()])
	for p: Dictionary in Broadway.palaces(plan):
		var lot: Dictionary = p.lot
		var c: Vector2 = lot.center
		var s: Vector2 = lot.size
		var side: int = p.side
		var face := c.x + s.x * 0.5 if side < 0 else c.x - s.x * 0.5
		var eye_x := x - float(side) * 7.0
		var yaw := 90.0 if side < 0 else -90.0
		print("PALACE %-12s %4d %s side %+d addr z %.1f lot z %.1f +-%.1f frontage %.1f depth %.1f off %.1f  EYE=%.1f,1.7,%.1f,%.0f,8" % [
			p.spec.id, int(p.spec.num), str(p.block), side, float(p.z), c.y, s.y * 0.5, s.y, s.x,
			maxf(absf(float(p.z) - c.y) - s.y * 0.5, 0.0), eye_x, c.y, yaw])
	quit()
