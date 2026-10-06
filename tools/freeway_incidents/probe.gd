extends Node
## The freeway incidents' schedule (FreewayIncidents): routes, how many incidents of each kind run
## at a few clocks, the share of time a stretch has one, the CMS gantries near a point and what
## they say, and EYEs for stills of an incident. Headless, seconds:
##   godot --headless --path . tools/freeway_incidents/probe.tscn
## SEED=n another seed; AT=x,z the point for the CMS list and the EYEs (default the 110 by downtown).
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var fw: Freeway = macro.freeway
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	for ri in fw.routes.size():
		print("route %d %s len %.0f width %.1f shoulder %.2f ramps %d" % [ri, fw.routes[ri].name, fw.length_of(ri), float(fw.routes[ri].width),
			float(Freeway.lane_layout(float(fw.routes[ri].width)).outer) - float(Freeway.lane_layout(float(fw.routes[ri].width)).edge),
			fw.ramps.filter(func(r: Dictionary) -> bool: return int(r.route) == ri).size()])
	var kinds := {}
	var samples := 0
	var stretches := 0
	for c in range(0, 40):
		var clock := 1000.0 + float(c) * 97.0
		for ri in fw.routes.size():
			var all := FreewayIncidents.running(fw, sd, ri, 0.0, fw.length_of(ri), clock)
			for inc: Dictionary in all:
				kinds[int(inc.kind)] = int(kinds.get(int(inc.kind), 0)) + 1
			if c == 0:
				stretches += ceili(fw.length_of(ri) / FreewayIncidents.ZONE) * 2
		samples += 1
	print("stretches ", stretches, " mean running per clock: ", kinds.keys().map(func(k: int) -> String: return "%s %.2f" % [FreewayIncidents.Kind.keys()[k], float(kinds[k]) / samples]))
	var at := Vector2(1989.0, 160.0)
	var at_env := OS.get_environment("AT").split(",", false)
	if at_env.size() == 2:
		at = Vector2(at_env[0].to_float(), at_env[1].to_float())
	var every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	var node := FreewayIncidents.new()
	node.plan = plan
	for ri in fw.routes.size():
		var near: Array = fw.nearest_on(ri, at)
		if float(near[1]) > 1500.0:
			continue
		var t := float(near[0])
		print("near route %d at t %.0f (%.0f m off)" % [ri, t, float(near[1])])
		var pts: PackedVector2Array = fw.routes[ri].points
		var i0 := maxi(0, int((t - 1500.0) / Freeway.STEP))
		var i1 := mini(pts.size() - 2, int((t + 1500.0) / Freeway.STEP))
		var idx := int(ceil(float(i0) / every)) * every
		while idx <= i1:
			for side: int in [1, -1]:
				if FreewayIncidents.has_cms(sd, ri, idx, float(side)) and not node._exit_board(fw, ri, idx, float(side)):
					var f := FreewayIncidents.cms_frame(fw, ri, idx, float(side))
					var eye := f.origin + f.basis.z * 70.0 - f.basis.x * 2.0
					var yaw := rad_to_deg(atan2(f.basis.z.x, f.basis.z.z))
					print("  CMS gantry %d side %d at (%.1f, %.1f, %.1f) t %.0f  EYE=%.1f,%.1f,%.1f,%.0f,-2  msg %s" % [idx, side, f.origin.x, f.origin.y, f.origin.z,
						float(fw._runs[ri][idx]), eye.x, eye.y - 1.0, eye.z, yaw, str(node.cms_message(fw, ri, idx, side))])
			idx += every
		# An incident spot nearby that site_ok() accepts, and an EYE onto it from the shoulder behind.
		for dt in [0.0, 120.0, -120.0, 240.0, -240.0, 360.0]:
			var tt := t + float(dt)
			if not FreewayIncidents.site_ok(fw, ri, tt, 1) or not FreewayIncidents.site_ok(fw, ri, tt, -1):
				continue
			for dir: int in [1, -1]:
				var lat := FreewayIncidents.shoulder_lat(fw, ri, dir)
				var p := FreewayIncidents.deck_point(fw, ri, tt - 30.0 * dir, lat * 1.05)
				var q := FreewayIncidents.deck_point(fw, ri, tt, lat)
				var yaw := rad_to_deg(atan2(-(q.x - p.x), -(q.z - p.z)))
				print("  spot FW_INCIDENT_AT=%d:%.0f:%d  EYE=%.1f,%.1f,%.1f,%.0f,-6" % [ri, tt, dir, p.x, p.y + 3.0, p.z, yaw])
				var lane3 := FreewayIncidents.lane_lat(fw, ri, Freeway.LANES - 1, dir)
				var lane1 := FreewayIncidents.lane_lat(fw, ri, 1, dir)
				for v: Array in [["behind", -24.0, lane3, 2.2, 0.0], ["side", 2.0, lane1, 7.5, 6.0], ["ahead", 32.0, lane3 * 0.9, 3.0, -4.0], ["debris", -30.0, lane1, 2.4, 0.0]]:
					var e := FreewayIncidents.deck_point(fw, ri, tt + float(v[1]) * dir, float(v[2]))
					var aim := FreewayIncidents.deck_point(fw, ri, tt + float(v[4]) * dir, lat if v[0] != "debris" else FreewayIncidents.lane_lat(fw, ri, 2, dir))
					var dx := aim.x - e.x
					var dz := aim.z - e.z
					var pitch := rad_to_deg(atan2(-(float(v[3]) - 0.6), Vector2(dx, dz).length()))
					print("    %s EYE=%.1f,%.1f,%.1f,%.1f,%.1f" % [v[0], e.x, e.y + float(v[3]), e.z, rad_to_deg(atan2(-dx, -dz)), pitch])
			break
	node.free()
	get_tree().quit()
