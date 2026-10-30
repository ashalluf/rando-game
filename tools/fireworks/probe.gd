extends Node
## Fireworks probe (Fireworks, shaders/fireworks.gdshaderinc): the sites on a seed with an EYE for
## each (the pier's end and a hill above, looking at the show), the shells of a whole act by type
## and phase, and which of the next 60 nights have a show. Headless, seconds:
##   godot --headless --path . res://tools/fireworks/probe.tscn      (SEED=n for another seed)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	for s in Fireworks.plan_sites(plan):
		var w: Vector3 = s.world
		print("SITE %s at (%.0f, %.1f, %.0f) zone=%d line=%s spread=%.0f h=%.0f..%.0f shore_x=%.0f" % [s.id, w.x, w.y, w.z, int(macro.zone_at(Vector2(w.x, w.z))), s.line, s.spread, s.h_min, s.h_max, s.shore_x])
		var counts := [0, 0, 0, 0, 0]
		var n := 0
		var max_life := 0.0
		for b in Fireworks.ACT_BINS:
			var sh := Fireworks.shell(12345, b, s.line, s.spread, s.h_min, s.h_max)
			if sh.is_empty():
				continue
			n += 1
			counts[sh.type] += 1
			max_life = maxf(max_life, float(sh.burst_t) + float(sh.life) - float(b) * Fireworks.BIN)
		print("  act: %d shells over %.0f s, by type %s, longest life %.2f s (slots cover %.1f)" % [n, Fireworks.ACT_BINS * Fireworks.BIN, counts, max_life, Fireworks.SLOTS * Fireworks.BIN])
		var nights := ""
		for d in 60:
			nights += "X" if Fireworks.show_tonight(sd, d, s.id) else "."
		print("  nights 0-59: ", nights)
		# EYEs looking at the middle of the show: from the pier's end (beach), and from the
		# highest ground 1-3 km round it that sees it.
		var target := w + Vector3(0.0, (float(s.h_min) + float(s.h_max)) * 0.5, 0.0)
		if s.id == "beach":
			_eye("pier", Vector3(-1100.0, 8.6, -330.0), target)
		var best := Vector3.ZERO
		for a in 72:
			for r: float in [1200.0, 1800.0, 2500.0]:
				var q := Vector2(w.x, w.z) + Vector2(cos(TAU * a / 72.0), sin(TAU * a / 72.0)) * r
				var h := plan.height_at(q)
				if int(macro.zone_at(q)) == int(MacroMap.Zone.HILLS) and h > best.y and h < 400.0:
					best = Vector3(q.x, h, q.y)
		if best.y > 0.0:
			_eye("hill", best + Vector3(0.0, 4.0, 0.0), target)
		var city := Vector2(w.x, w.z) + Vector2(900.0, 600.0) if s.id == "beach" else Vector2(w.x, w.z) + Vector2(300.0, 1100.0)
		_eye("street", Vector3(city.x, plan.height_at(city) + 1.8, city.y), target)
	get_tree().quit()


func _eye(label: String, e: Vector3, t: Vector3) -> void:
	var d := (t - e).normalized()
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(asin(d.y))
	print("  EYE %s=%.1f,%.1f,%.1f,%.1f,%.1f  (%.0f m)" % [label, e.x, e.y, e.z, yaw, pitch, e.distance_to(t)])
