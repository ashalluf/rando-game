extends RefCounted
## The coast_highway refcam (Rc5CoastHighway, CoastFlutes), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## The camera row; the bluff fluted (the face varies along the shore, never under the road's bed,
## the bench and the sand untouched, off with the switch); the traffic's count by the hour and its
## first fill (in reach, spaced, never on the player); a beach house's real garage door and its
## end wall's glass.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var ch: CoastHighway = macro.coast_highway if macro else null
	if ch == null:
		_t._check(false, "rc5 coast highway: the stretch is planned")
		return
	_flutes(ch, macro)
	_traffic(ch)
	_houses(ch)


func _camera_row() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var row := {}
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for cam: Dictionary in data.get("cameras", []):
				if cam.get("name", "") == "coast_highway":
					row = cam
	_t._check(not row.is_empty() and absf(float(row.get("hour", 0.0)) - 17.0) < 0.01 and String(row.get("weather", "")) == "clear",
		"rc5 coast highway: the camera row is in cameras_w8.json at 17:00 clear")


func _flutes(ch: CoastHighway, macro: MacroMap) -> void:
	var was := CoastFlutes.enabled
	var on := PackedFloat32Array()
	var off := PackedFloat32Array()
	var bench_moved := 0.0
	var sand_moved := 0.0
	var below_bed := 0
	var z := ch.z_north + 40.0
	while z < ch.z_full - 90.0:
		var p := ch.at(CoastHighway.TOE + 22.0, z)
		var road := ch.at(CoastHighway.CENTRE, z)
		var sand := ch.at(CoastHighway.WALL - 6.0, z)
		CoastFlutes.enabled = true
		var h_on := macro.height_at(p)
		var r_on := macro.height_at(road)
		var s_on := macro.height_at(sand)
		CoastFlutes.enabled = false
		var h_off := macro.height_at(p)
		bench_moved = maxf(bench_moved, absf(r_on - macro.height_at(road)))
		sand_moved = maxf(sand_moved, absf(s_on - macro.height_at(sand)))
		if h_on < ch.bed_y(z) - 0.01:
			below_bed += 1
		on.append(h_on)
		off.append(h_off)
		z += 3.0
	CoastFlutes.enabled = was
	var cut := 0
	var deepest := 0.0
	for i in on.size():
		var dz := off[i] - on[i]
		if dz > 0.5:
			cut += 1
		deepest = maxf(deepest, dz)
	var n := on.size()
	_t._check(n > 50 and cut > n / 5 and cut < n * 4 / 5 and deepest > 2.0,
		"rc5 coast highway: the bluff's face is fluted by gullies (%d of %d samples cut, deepest %.1f m)" % [cut, n, deepest])
	_t._check(bench_moved < 0.001 and sand_moved < 0.001 and below_bed == 0,
		"rc5 coast highway: the flutes leave the road, the sand and the bed alone (road %.3f, sand %.3f, %d under the bed)" % [bench_moved, sand_moved, below_bed])
	var g1 := CoastFlutes.gully(ch.seed, -1200.0, 12.0)
	_t._check(g1 == CoastFlutes.gully(ch.seed, -1200.0, 12.0) and g1 >= 0.0 and g1 <= 1.0, "rc5 coast highway: the gully field is pure and 0..1")


func _traffic(ch: CoastHighway) -> void:
	var rush := Rc5CoastHighway.wanted(6, 17.0)
	var night := Rc5CoastHighway.wanted(6, 3.0)
	_t._check(rush >= 10 and night <= 4 and night >= 2, "rc5 coast highway: cars a direction follow the hour (17:00 %d, 03:00 %d)" % [rush, night])
	var ps := (ch.z_north + ch.z_full) * 0.5
	var lo := ch.z_north + 80.0
	var hi := ch.z_south + 300.0
	var slots := Rc5CoastHighway.fill_slots(ch.seed, 1, rush, ps, 380.0, lo, hi, 35.0)
	var ok := slots.size() >= rush - 2
	var near := 0
	for i in slots.size():
		var s := float(slots[i][0])
		ok = ok and s >= lo and s <= hi and absf(s - ps) >= 12.0
		if absf(s - ps) < 160.0:
			near += 1
		for j in range(i + 1, slots.size()):
			if int(slots[i][1]) == int(slots[j][1]) and absf(float(slots[j][0]) - s) < 35.0:
				ok = false
	_t._check(ok and near > 0, "rc5 coast highway: the first fill spreads the cars over the reach, near road too (%d slots, %d within 160 m)" % [slots.size(), near])


func _houses(ch: CoastHighway) -> void:
	var g := CoastHighwayBuild.Geo.new()
	var b := Basis.IDENTITY
	var P := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z)
	var made := Rc5CoastHighway.garage_door(g, P, b, -1.5, 1.5, 0.0, 2.35, -0.14, -b.z, -1.0, Color(0.62, 0.52, 0.40), 5)
	var slats := (g.s.get("h_door", {}).get("v", PackedVector3Array()) as PackedVector3Array).size()
	var g2 := CoastHighwayBuild.Geo.new()
	Rc5CoastHighway.garage_door(g2, P, b, -1.5, 1.5, 0.0, 2.35, -0.14, -b.z, -1.0, Color(0.94, 0.93, 0.90), 5)
	var panels := (g2.s.get("h_door", {}).get("v", PackedVector3Array()) as PackedVector3Array).size()
	_t._check(made and slats > 200 and panels > 100, "rc5 coast highway: a garage door is real slats or panels (%d / %d vertices)" % [slats, panels])
	# An end house of a run gets glass on its open side.
	var found := false
	for hs: Dictionary in ch.houses:
		for sx: float in [-1.0, 1.0]:
			var edge := float(hs.z1) if sx > 0.0 else float(hs.z0)
			if ch.house_at(edge + sx * 3.5, 0.0).is_empty():
				var holes: Array = []
				Rc5CoastHighway.side_windows(ch, hs, sx, float(hs.depth), 4.3, 7.4, holes)
				found = found or holes.size() >= 1
	_t._check(found, "rc5 coast highway: a house at the end of a run opens its side to the view")
	_t._check(Rc5CoastHighway.apron_material() is ShaderMaterial, "rc5 coast highway: the apron's concrete is the road shader's")
