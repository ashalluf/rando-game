extends Node
## Ocean traffic probe (OceanTraffic, Vessel, VesselMesh): every route sampled every 20 m against
## the sea (sea_room() with its margin), the anchorage, every hull's triangle counts by level, and a
## map of the sea with the routes drawn on it. Headless, seconds:
##   godot --headless --path . tools/ocean_traffic/probe.tscn   (OUT=map.png; a scene, so the
##   autoloads exist before Vessel compiles)
const MARGINS := {"coast": 150.0, "bay": 150.0, "ferry": 100.0, "tug": 60.0, "pilot": 60.0}


func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var ot := OceanTraffic.new()
	ot.macro = macro
	for lm: Dictionary in Landmarks.all():
		if (lm.id as String).ends_with("pier"):
			ot._pier_zones.append([(lm.anchor as Vector2) + Vector2(-160.0, 0.0), 380.0])
	ot._build_lanes()
	var bad_total := 0
	for name: String in ot.lanes:
		var pts: PackedVector2Array = ot.lanes[name]
		var cum: PackedFloat32Array = Vessel.cumulate(pts)
		var total: float = cum[cum.size() - 1]
		var bad := 0
		var first := Vector2.INF
		var s := 0.0
		while s < total:
			var p: Vector2 = Vessel.loop_point(pts, cum, s)
			if not ot.sea_room(p, MARGINS.get(name, 100.0)):
				bad += 1
				if first == Vector2.INF:
					first = p
			s += 20.0
		bad_total += bad
		print("lane %-6s points=%d length=%.0f m off-water samples=%d first=%s" % [name, pts.size(), total, bad, first])
	for a: Vector2 in OceanTraffic.ANCHORAGE:
		print("anchorage ", a, " room(260)=", ot.sea_room(a, 260.0))
	for h: Vector2 in OceanTraffic.SAIL_HOMES:
		print("sail home ", h, " room(300)=", ot.sea_room(h, 300.0))
	for k in 7:
		for v in 2:
			var line := "kind %d v%d:" % [k, v]
			for lv in 3:
				var m: ArrayMesh = VesselMesh.hull(k, v, lv)
				line += " %d" % ((m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3)
			print(line)
	for lv in 3:
		var m: ArrayMesh = VesselMesh.main_sail(0, 1.0, lv)
		var j: ArrayMesh = VesselMesh.jib(0, 1.0, lv)
		print("sails lv%d main=%d jib=%d" % [lv, (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, (j.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])
	print("PROBE off-water total=", bad_total)
	var out := OS.get_environment("OUT")
	if out != "":
		var x0 := -9000.0
		var z0 := -6000.0
		var step := 40.0
		var w := 400
		var h := 600
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for j in h:
			for i in w:
				var p := Vector2(x0 + i * step, z0 + j * step)
				img.set_pixel(i, j, Color(0.1, 0.25, 0.5) if macro.zone_at(p) == MacroMap.Zone.OCEAN else Color(0.5, 0.48, 0.4))
		var cols := {"coast": Color.YELLOW, "bay": Color.ORANGE, "ferry": Color.WHITE, "tug": Color.RED, "pilot": Color.MAGENTA}
		for name: String in ot.lanes:
			var pts: PackedVector2Array = ot.lanes[name]
			var cum: PackedFloat32Array = Vessel.cumulate(pts)
			var s := 0.0
			while s < cum[cum.size() - 1]:
				var p: Vector2 = Vessel.loop_point(pts, cum, s)
				var px := int((p.x - x0) / step)
				var pz := int((p.y - z0) / step)
				if px >= 0 and pz >= 0 and px < w and pz < h:
					img.set_pixel(px, pz, cols.get(name, Color.GREEN))
				s += 20.0
		for a: Vector2 in OceanTraffic.ANCHORAGE + OceanTraffic.SAIL_HOMES:
			var px := int((a.x - x0) / step)
			var pz := int((a.y - z0) / step)
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if px + dx >= 0 and pz + dz >= 0 and px + dx < w and pz + dz < h:
						img.set_pixel(px + dx, pz + dz, Color.GREEN)
		img.save_png(out)
	ot.free()
	get_tree().quit()
