extends Node
## Stunt ramps probe: every site StuntRamps plans (river, freeway, pier; car parks and vacant lots in
## a square round AT), with an EYE line for tools/glshot/still_shot.gd looking at each. Headless:
##   godot --headless --path . res://tools/stunt_ramps/probe.tscn   (SEED=n, AT=x,z, RADIUS=m)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("setup ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	Footbridges.near(plan, Rect2(-3000, -4000, 9000, 11000))
	print("footbridges ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	StuntRamps.river_sites(plan)
	print("river ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	StuntRamps.freeway_sites(plan)
	print("freeway ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	var sites := StuntRamps.all_sites(plan)
	print("sites ms=", Time.get_ticks_msec() - t0, " n=", sites.size())
	var at := Vector2(2000.0, 1000.0)
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		at = Vector2(float(p[0]), float(p[1]))
	var radius := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 2500.0
	t0 = Time.get_ticks_msec()
	var r := Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var b0 := plan.block_index_at(r.position)
	var b1 := plan.block_index_at(r.end)
	var dirt := 0
	for bx in range(b0.x, b1.x + 1):
		for bz in range(b0.y, b1.y + 1):
			var cp := StuntRamps.car_park_site(plan, bx, bz)
			if not cp.is_empty():
				sites.append(cp)
			if OS.get_environment("DIRT") == "0":
				continue
			var b := plan.block(bx, bz)
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			for lot: Dictionary in plan.lots(bx, bz):
				if VacantLots.kind_of(plan, bx, bz, lot) != VacantLots.VACANT:
					continue
				var vp := VacantLots.plan_lot(plan, bx, bz, lot, VacantLots.VACANT)
				var ds := StuntRamps.vacant_site(plan, lot, vp)
				if not ds.is_empty():
					sites.append(ds)
					dirt += 1
	print("blocks ms=", Time.get_ticks_msec() - t0, " dirt=", dirt)
	var kinds := {}
	for s: Dictionary in sites:
		var k: String = StuntRamps.Kind.keys()[int(s.kind)]
		kinds[k] = int(kinds.get(k, 0)) + 1
		var p: Vector3 = s.p
		var yaw: float = s.yaw
		var fwd := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		# The eye: off to the right and ahead of the foot, looking back at the piece.
		var mid := Vector2(p.x, p.z) + fwd * 4.0
		var eye := mid + right * 14.0 - fwd * 6.0
		var d := mid - eye
		print("%s %s p=(%.1f,%.2f,%.1f) yaw=%.1f EYE=%.1f,%.1f,%.1f,%.1f,%.1f" % [s.id, k, p.x, p.y, p.z, rad_to_deg(yaw),
			eye.x, p.y + 3.0, eye.y, rad_to_deg(atan2(-d.x, -d.y)), -8.0])
	print("KINDS ", kinds)
	get_tree().quit()
