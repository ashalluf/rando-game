extends Node
## The walk of fame (StarBoulevard) for a seed: the boulevard picked, its stretch, the palace and
## EYEs for tools/glshot/still_shot.gd (a pavement view along the stars, the palace's forecourt
## from the kerb opposite, an oblique from above).
##   godot --headless --path . tools/star_boulevard/probe.tscn [-- --seed=N]
func _ready() -> void:
	await get_tree().process_frame
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
	var t0 := Time.get_ticks_usec()
	var p: Dictionary = StarBoulevard.plan_for(plan)
	print("PLAN us %d" % (Time.get_ticks_usec() - t0))
	if p.is_empty():
		print("NO WALK")
		get_tree().quit()
		return
	var r0: Rect2 = plan.block(int(p.k0), int(p.road)).rect
	var r1: Rect2 = plan.block(int(p.k1), int(p.road)).rect
	print("WALK %s road %d z %.1f width %.1f blocks %d..%d x %.1f..%.1f" % [p.name, int(p.road), float(p.z), float(p.width), int(p.k0), int(p.k1), r0.position.x, r1.end.x])
	for k in range(int(p.k0), int(p.k1) + 1):
		for bz in [int(p.road) - 1, int(p.road)]:
			var sd := StarBoulevard.block_side(plan, k, bz)
			for lot: Dictionary in plan.lots(k, bz):
				if StarBoulevard.lot_fronts(plan, k, bz, sd, lot):
					print("  LOT %d,%d %s size %s parking %s" % [k, bz, str(lot.center), str(lot.size), str(lot.get("parking", false))])
	var pal: Dictionary = p.palace
	if not pal.is_empty():
		var lot: Dictionary = pal.lot
		var c: Vector2 = lot.center
		var s: Vector2 = lot.size
		var side: int = pal.side
		var front := c.y - float(side) * s.y * 0.5
		var eye_z := float(p.z) - float(side) * (float(p.width) * 0.5 + 1.5)
		var yaw := 0.0 if side < 0 else 180.0
		print("PALACE block %s side %+d lot %.1f,%.1f size %.1fx%.1f front z %.1f" % [str(pal.block), side, c.x, c.y, s.x, s.y, front])
		print("EYE_PALACE=%.1f,1.7,%.1f,%.0f,8" % [c.x, eye_z, yaw])
		print("EYE_FORECOURT=%.1f,2.2,%.1f,%.0f,-14" % [c.x + 6.0, front - float(side) * 1.0, yaw + 25.0])
		print("BUSZONE %s" % str(StarBoulevard.bus_zone(plan)))
	var nz := float(p.z) - (float(p.width) * 0.5 + 3.3)
	var mid := (r0.position.x + r1.end.x) * 0.5
	print("EYE_ALONG=%.1f,1.6,%.1f,-90,-8" % [mid - 60.0, nz])
	print("EYE_DOWN=%.1f,2.4,%.1f,-90,-40" % [mid - 10.0, nz])
	print("EYE_HIGH=%.1f,40,%.1f,-70,-25" % [mid - 120.0, float(p.z) + 30.0])
	for bx in range(int(p.k0), int(p.k1) + 1):
		for bz in [int(p.road) - 1, int(p.road)]:
			var side := StarBoulevard.block_side(plan, bx, bz)
			var rect: Rect2 = plan.block(bx, bz).rect
			var n := 0
			for i in StarBoulevard.MAX_CHARACTERS:
				var cs := StarBoulevard.character_spot(plan, bx, bz, rect, side, i)
				if not cs.is_empty():
					n += 1
					print("  CHAR %d,%d %s at %s" % [bx, bz, StreetCharacter.COSTUMES[int(cs.costume)].name, str(cs.at)])
	get_tree().quit()
