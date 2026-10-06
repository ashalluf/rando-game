extends SceneTree
## Where the flyable helicopters wait (FlyableHeli, HeliSpot, HeliPads): prints the airport
## heliport's pads with the ground under them and what is near, the police HQ's site, and the
## hospitals. Headless, seconds:
##   godot --headless --path . --script tools/heli/probe.gd
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("taxiway_z=%.1f width=%.1f runways=%s apron spots=%s" % [macro.taxiway_z, macro.taxiway_width, str(macro.runway_zs), str(macro.apron_spots)])
	for g: Dictionary in Airport.gates():
		print("gate nose=%s centre=%s" % [g.get("nose"), g.get("centre")])
	for p: Vector2 in HeliPads.airport_pads():
		var area := Rect2(p - Vector2(10, 10), Vector2(20, 20))
		var kinds := []
		for piece: Array in Airport.ground_pieces(macro, area):
			kinds.append(piece[2])
		print("heliport pad %s zone=%s ground kinds=%s near_gate=%s" % [p, MacroMap.zone_name(macro.zone_at(p)), str(kinds), Airport.near_gate(p, 25.0)])
	var masts: Array = Airport.mast_spots(macro)
	var stag: Array = []
	var rf := Airport.apron_face()
	for e: float in [-1.0, 1.0]:
		var a := e * (Airport.CONCOURSE_ARC + 0.012)
		stag.append(Airport.arc_point(a, rf - 6.0) + Airport.arc_tangent(a) * e * 8.0)
	print("staging ", stag)
	var x := -630.0
	while x < 0.0:
		for z: float in [745.0, 750.0, 755.0]:
			var p := Vector2(x, z)
			var ok := macro.airport_rect.grow(-15.0).has_point(p) and not Airport.near_gate(p, 20.0)
			for piece: Array in Airport.ground_pieces(macro, Rect2(p - Vector2(12, 12), Vector2(24, 24))):
				ok = ok and int(piece[2]) == Airport.G_APRON
			for sp: Array in macro.apron_spots:
				ok = ok and (sp[0] as Vector2).distance_to(p) >= 45.0
			for m: Array in masts:
				ok = ok and (m[0] as Vector2).distance_to(p) >= 18.0
			for st: Vector2 in stag:
				ok = ok and st.distance_to(p) >= 40.0
			if ok:
				print("candidate ", p)
		x += 10.0
	var hq := PoliceStation.hq(plan)
	print("police hq: ", hq.get("block"), " front=", hq.get("front"))
	for cx in range(-4, 5):
		for cz in range(-3, 6):
			var st := PoliceStation.for_cell(plan, Vector2i(cx, cz))
			if st.is_empty():
				continue
			print("station %s front %s pad %s storeys %d" % [st.key, st.get("front"), HeliPads.station_pad(false, st.key), int(st.storeys)])
	quit()
