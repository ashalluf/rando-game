extends RefCounted
## The harbour's lights (Lighthouses, LighthouseKit, LighthouseBeacon): checks for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. The look is judged
## in stills (docs/HANDOFF.md, the lighthouses section); here: where everything stands, the pad in
## the ground, the pieces' builds and collision, the beacons' clock, the shaders' contract, and the
## A/B switch.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not Lighthouses.enabled():
		_t._check(true, "lighthouses are off (LIGHTHOUSES=0): nothing to check")
		return
	var plan: CityPlan = city.get("plan")
	_entries(plan)
	_pad(plan)
	_breakwater_clear(plan)
	_beacon_clock()
	_shaders()
	_far_copies(city)
	await _near_builds(city, plan)
	_switch(plan)


## Every piece is a landmark: the lighthouse on the headland's hills, the breakwater's pieces end
## to end at sea, the gate light at its head.
func _entries(plan: CityPlan) -> void:
	var ids: Dictionary = {}
	for lm: Dictionary in Landmarks.all():
		if Lighthouses.is_piece(lm.id):
			ids[lm.id] = lm
	var segs := Lighthouses.segments()
	var ok := ids.has(Lighthouses.LIGHT_ID) and ids.has(Lighthouses.GATE_ID) and ids.size() == segs.size() + 2
	var at_sea := 0
	var gaps := 0.0
	for k in segs.size():
		var s: Dictionary = segs[k]
		if plan.macro.zone_at((s.a + s.b) * 0.5) == MacroMap.Zone.OCEAN:
			at_sea += 1
		if k > 0:
			gaps = maxf(gaps, (s.a as Vector2).distance_to((segs[k - 1] as Dictionary).b))
	var lz := plan.macro.zone_at(Lighthouses.LIGHT_AT)
	var gz := plan.macro.zone_at(Lighthouses.gate_at())
	_t._check(ok and at_sea >= segs.size() - 2 and gaps < 0.01 and lz == MacroMap.Zone.HILLS and gz == MacroMap.Zone.OCEAN
		and Lighthouses.breakwater_length() > 1200.0,
		"lighthouses: %d landmark pieces, %d of %d breakwater pieces at sea end to end (%.0f m), the light on %s, the gate at %s"
			% [ids.size(), at_sea, segs.size(), Lighthouses.breakwater_length(), MacroMap.zone_name(lz), MacroMap.zone_name(gz)])


## The pad: level to its radius, handed back to the ground by its reach, and nowhere steeper
## than its cut / fill banks allow.
func _pad(plan: CityPlan) -> void:
	var m := plan.macro
	var y := Lighthouses.pad_y(m)
	var flat := 0.0
	var steep := 0.0
	var off := 0
	for a in 16:
		var dir := Vector2(cos(TAU * a / 16.0), sin(TAU * a / 16.0))
		for r in [0.0, 6.0, 12.0, 18.0, Lighthouses.PAD_RADIUS - 0.5]:
			flat = maxf(flat, absf(m.height_at(Lighthouses.LIGHT_AT + dir * r) - y))
		var prev := m.height_at(Lighthouses.LIGHT_AT + dir * Lighthouses.PAD_RADIUS)
		var r := Lighthouses.PAD_RADIUS + 1.0
		while r <= Lighthouses.PAD_REACH - 6.0:
			var h := m.height_at(Lighthouses.LIGHT_AT + dir * r)
			steep = maxf(steep, absf(h - prev))
			prev = h
			r += 1.0
		var outside := Lighthouses.LIGHT_AT + dir * (Lighthouses.PAD_REACH + 1.0)
		if absf(Lighthouses.carve(m, outside, 3.0) - 3.0) > 1e-4:
			off += 1
	_t._check(flat < 0.01 and steep < 1.08 and off == 0 and y > 8.0,
		"lighthouses: the pad is level at %.2f m (worst %.3f), its banks at most %.2f m a metre, untouched past its reach (%d off)" % [y, flat, steep, off])
	var covered := Lighthouses.covers(Lighthouses.LIGHT_AT + Vector2(8.0, -5.0), 0.0) and Lighthouses.covers(Lighthouses.segments()[5].a, 0.0)
	var free := not Lighthouses.covers(Lighthouses.LIGHT_AT + Vector2(-120.0, -80.0), 2.0)
	_t._check(covered and free, "lighthouses: the hills' planting keeps off the pad and the breakwater, not off the hills round them")


## The breakwater keeps out of the port, the harbour's berth and the cargo ship, and off every
## city block.
func _breakwater_clear(plan: CityPlan) -> void:
	var m := plan.macro
	var hits: Array[String] = []
	var reach := Lighthouses.half_width_at(Lighthouses.FOOT_Y)
	var s := 0.0
	var total := Lighthouses.breakwater_length()
	while s <= total:
		var p := _at_s(s)
		for side in [-1.0, 0.0, 1.0]:
			var q: Vector2 = p + _normal_at(s) * reach * float(side)
			if m.port_rect.has_point(q) or m.harbor_rect.has_point(q):
				hits.append("port at s %.0f" % s)
			if m.zone_at(q) == MacroMap.Zone.CITY:
				hits.append("city at s %.0f" % s)
		s += 5.0
	var ship := Vector2(3065.0, 6541.0)
	var ship_d := Lighthouses.nearest(ship).x
	_t._check(hits.is_empty() and ship_d > 250.0,
		"lighthouses: the breakwater stays off the port, the berth and the city (%s), %.0f m from the cargo ship" % [", ".join(hits.slice(0, 4)), ship_d])


func _at_s(s: float) -> Vector2:
	for seg: Dictionary in Lighthouses.segments():
		if s <= float(seg.s1) + 1e-3:
			var t := (s - float(seg.s0)) / maxf(float(seg.s1) - float(seg.s0), 1e-3)
			return (seg.a as Vector2).lerp(seg.b, clampf(t, 0.0, 1.0))
	return Lighthouses.gate_at()


func _normal_at(s: float) -> Vector2:
	for seg: Dictionary in Lighthouses.segments():
		if s <= float(seg.s1) + 1e-3:
			var d := ((seg.b as Vector2) - (seg.a as Vector2)).normalized()
			return Vector2(-d.y, d.x)
	return Vector2.UP


## The rotors turn once a period, clockwise seen from above, from the real clock: every copy of a
## light at the same angle at the same moment.
func _beacon_clock() -> void:
	var p := 20.0
	var a0 := LighthouseBeacon.angle_at(100.0, p, 0.13)
	var a1 := LighthouseBeacon.angle_at(100.0 + p, p, 0.13)
	var a2 := LighthouseBeacon.angle_at(101.0, p, 0.13)
	var d := wrapf(a2 - a0, -PI, PI)
	_t._check(absf(wrapf(a1 - a0, -PI, PI)) < 1e-4 and d < 0.0 and absf(absf(d) - TAU / p) < 1e-4,
		"lighthouses: a rotor turns once in its period (%.0f s), clockwise, from the clock" % p)
	var ok := true
	for id: String in Lighthouses.LIGHTS:
		var spec: Dictionary = Lighthouses.LIGHTS[id]
		ok = ok and float(spec.period) > 4.0 and int(spec.beams) >= 1 and int(spec.beams) <= 4 and float(spec.length) > 500.0
	_t._check(ok, "lighthouses: both lights have a period, 1-4 beams (the shaders' loop) and a reach")


## The far lamp and the lens read the beam's axis off the rotor (MODEL_MATRIX[0]), so nothing per
## frame is set from script; the lamp keeps aircraft_lights' never-smaller-than-a-few-pixels rule.
func _shaders() -> void:
	var lamp := FileAccess.get_file_as_string("res://shaders/lighthouse_lamp.gdshader")
	var lens := FileAccess.get_file_as_string("res://shaders/lighthouse_lens.gdshader")
	var beam := FileAccess.get_file_as_string("res://shaders/lighthouse_beam.gdshader")
	var stone := FileAccess.get_file_as_string("res://shaders/armour_stone.gdshader")
	var ok := lamp.contains("MODEL_MATRIX[0]") and lamp.contains("min_angle") and lamp.contains("max_depth") and lamp.contains("k < 4")
	ok = ok and lens.contains("MODEL_MATRIX[0]") and lens.contains("i < 4")
	ok = ok and beam.contains("blend_add") and beam.contains("lamp_factor")
	ok = ok and stone.contains("origin_shift") and stone.contains("color_space.gdshaderinc")
	for path in ["res://shaders/lighthouse_lamp.gdshader", "res://shaders/lighthouse_lens.gdshader", "res://shaders/lighthouse_beam.gdshader",
			"res://shaders/armour_stone.gdshader", "res://shaders/breakwater_foam.gdshader"]:
		ok = ok and load(path) is Shader
	_t._check(ok, "lighthouses: the lamp and lens turn with their rotor, the beam is additive and lamp-lit, the armour is in true world space")


## CityStreamer keeps a far copy of every piece, each with its rotor where it has a lantern.
func _far_copies(city: Node3D) -> void:
	var far: Dictionary = city.get("_far_landmarks")
	var missing: Array[String] = []
	var rotors := 0
	for lm: Dictionary in Lighthouses.entries():
		if not far.has(lm.id):
			missing.append(lm.id)
			continue
		rotors += (far[lm.id] as Node).find_children("Rotor", "", true, false).size()
	_t._check(missing.is_empty() and rotors == 2, "lighthouses: a far copy of every piece (%d missing), two rotors among them" % missing.size())


## The near pieces: the house and its lantern, the gate light, a breakwater piece with its armour;
## standing on the walkway and on the gallery works (rays onto the collision).
func _near_builds(city: Node3D, plan: CityPlan) -> void:
	var holder := Node3D.new()
	holder.name = "LighthouseChecks"
	city.add_child(holder)
	holder.position = -WorldState.world_offset
	var statics := StaticBody3D.new()
	statics.collision_mask = 0
	holder.add_child(statics)
	var t0 := Time.get_ticks_usec()
	var pieces: Dictionary = {}
	for lm: Dictionary in Lighthouses.entries():
		if lm.id == Lighthouses.LIGHT_ID or lm.id == Lighthouses.GATE_ID or lm.id == Lighthouses.SEG_PREFIX + "6":
			var n := Node3D.new()
			holder.add_child(n)
			Landmarks.build(lm, n, statics, plan, true)
			pieces[lm.id] = n
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var house: Node = pieces[Lighthouses.LIGHT_ID]
	var gate: Node = pieces[Lighthouses.GATE_ID]
	var seg: Node = pieces[Lighthouses.SEG_PREFIX + "6"]
	var rotor := house.find_child("Rotor", true, false) as LighthouseBeacon
	var ok := house.find_child("LighthouseMesh", true, false) != null and rotor != null
	ok = ok and rotor.find_child("Lens", true, false) != null and rotor.find_child("Beams", true, false) != null and rotor.find_child("Lamp", true, false) != null
	ok = ok and is_equal_approx(rotor.period, float(Lighthouses.LIGHTS[Lighthouses.LIGHT_ID].period))
	ok = ok and gate.find_child("GateLightMesh", true, false) != null and gate.find_child("Rotor", true, false) != null
	var stones := 0
	for mm in seg.find_children("Batch_bw_stone_*", "MultiMeshInstance3D", true, false):
		stones += (mm as MultiMeshInstance3D).multimesh.instance_count
	_t._check(ok and stones > 400 and ms < 400.0,
		"lighthouses: near pieces built in %.0f ms (cached meshes): the house, its lantern's rotor, lens, beams and lamp, the gate light, %d armour stones on a piece" % [ms, stones])
	for i in 3:
		await _t.get_tree().physics_frame
	var space := holder.get_world_3d().direct_space_state
	var seg6: Dictionary = Lighthouses.segments()[6]
	var mid: Vector2 = (seg6.a + seg6.b) * 0.5
	var cap := _ray_y(space, WorldState.to_local(Vector3(mid.x, 30.0, mid.y)))
	var py := Lighthouses.pad_y(plan.macro)
	var gallery := _ray_y(space, WorldState.to_local(Vector3(Lighthouses.LIGHT_AT.x, py + 30.0, Lighthouses.LIGHT_AT.y) + Vector3(2.15, 0.0, 0.0).rotated(Vector3.UP, 0.4)))
	_t._check(absf(cap - Lighthouses.CAP_TOP) < 0.1 and gallery > py + LighthouseKit.TOWER_TOP - 0.5,
		"lighthouses: you can stand on the walkway (hit at %.2f m, cap %.2f) and the lantern gallery (%.1f m over the pad)" % [cap, Lighthouses.CAP_TOP, gallery - py])
	holder.queue_free()


func _ray_y(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -999.0
	return (hit.position as Vector3).y


## LIGHTHOUSES=0: no entries and no pad (the ground as it was).
func _switch(plan: CityPlan) -> void:
	var was := Lighthouses._enabled
	Lighthouses._enabled = 0
	var none := Lighthouses.entries().is_empty()
	var h := Lighthouses.carve(plan.macro, Lighthouses.LIGHT_AT, 3.25)
	var covers := Lighthouses.covers(Lighthouses.LIGHT_AT, 0.0)
	Lighthouses._enabled = was
	_t._check(none and is_equal_approx(h, 3.25) and not covers, "lighthouses: LIGHTHOUSES=0 builds none of it and carves nothing")
