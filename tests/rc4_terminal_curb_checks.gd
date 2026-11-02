extends RefCounted
## The airport's departures kerb (TerminalCurb, CurbTraveller; the terminal_curb reference camera in
## tools/refcams/cameras_w7.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the travellers' spots are pure, on the strip, clear of the columns, the vestibules, the
## pylons and each other, each with its luggage beside it; the luggage and the carts are real-sized
## meshes; the kerb lane's drop-offs stop a car at its spot on its hazards, pulled toward the kerb,
## and let it go after its dwell (and leave the inner loop alone); a share of the loop's cars are
## taxis and shuttle vans; the build lays the kerb, its signs and planting (and the glass
## vestibules come through AirportTerminal); the camera row stands on the kerb under the roof;
## TERMINAL_CURB=0 puts every number back.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := TerminalCurb.enabled
	TerminalCurb.enabled = true
	_spots()
	_meshes()
	_drop_offs()
	_cars()
	_build(city)
	_camera()
	TerminalCurb.enabled = false
	var car := Vehicle.new()
	car.traffic = {"loop": 0, "t": 60.0}
	var r: Array = TerminalCurb.loop_speed(car, 0, 3.0, 0.1)
	_t._check(float(r[0]) == 3.0 and float(r[1]) == 0.0 and not car.traffic.has("tc_lap")
		and TerminalCurb.walkers(45) == 45 and TerminalCurb.loop_car(12345) == null,
		"TERMINAL_CURB=0: the loop drives as before, the full kerb crowd, no taxis or shuttles picked")
	car.free()
	var holder := Node3D.new()
	TerminalCurb.build(holder, null, _macro(city), true)
	_t._check(holder.get_child_count() == 0, "TERMINAL_CURB=0: nothing is laid on the kerb")
	holder.free()
	TerminalCurb.enabled = was


func _macro(city: Node) -> MacroMap:
	var plan = city.get("plan") if city else null
	return plan.macro if plan else null


func _spots() -> void:
	var a := TerminalCurb.spots(1337)
	var b := TerminalCurb.spots(1337)
	_t._check(a.size() >= 30 and a.size() == b.size(), "the kerb has its travellers (%d spots) and the same ones every time" % a.size())
	var same := true
	for i in mini(a.size(), b.size()):
		if (a[i].p as Vector2) != (b[i].p as Vector2) or int(a[i].seed) != int(b[i].seed):
			same = false
	_t._check(same, "the spots are pure (a hash of the seed and the place)")
	var ok := true
	var bad := ""
	for s: Dictionary in a:
		var p: Vector2 = s.p
		if p.y < 625.2 or p.y > 633.0 or p.x < TerminalCurb.X0 or p.x > TerminalCurb.X1:
			ok = false
			bad = "off the strip %s" % p
		for cx in TerminalCurb.column_xs():
			if Vector2(cx, TerminalCurb.COLUMN_Z).distance_to(p) < 0.9:
				ok = false
				bad = "on a column %s" % p
		for o: Dictionary in a:
			if o != s and (o.p as Vector2).distance_to(p) < 0.35:
				ok = false
				bad = "two people in one place %s" % p
		if (s.bags as Array).is_empty() or (s.bags as Array).size() > 2:
			ok = false
			bad = "no luggage %s" % p
		for bag: Array in s.bags:
			var d := (bag[1] as Vector2).distance_to(p)
			if d < 0.25 or d > 0.9:
				ok = false
				bad = "a bag %.2f m from its owner" % d
	_t._check(ok, "every traveller stands on the kerb, clear of the columns and each other, their bags at their side %s" % bad)
	var kerb := 0
	var door := 0
	for s: Dictionary in a:
		if (s.p as Vector2).y < 626.6:
			kerb += 1
		elif (s.p as Vector2).y > 631.4:
			door += 1
	_t._check(kerb >= 5 and door >= 3, "some wait at the kerb (%d), some are going in at the doors (%d)" % [kerb, door])
	_t._check(TerminalCurb.spots(7).size() > 20 and TerminalCurb.spots(7)[0].p != a[0].p, "another seed, other travellers")


func _meshes() -> void:
	var big := TerminalCurb.bag_mesh(0).get_aabb()
	_t._check(big.size.y > 0.7 and big.size.y < 0.85 and big.size.x > 0.4 and big.size.x < 0.6,
		"a large spinner case is real-sized (%s)" % big.size)
	var carry := TerminalCurb.bag_mesh(1).get_aabb()
	_t._check(carry.size.y > 0.95 and carry.size.y < 1.15 and carry.size.x < 0.45, "a carry-on with its handle up stands about a metre (%s)" % carry.size)
	var duffel := TerminalCurb.bag_mesh(2).get_aabb()
	_t._check(duffel.size.y < 0.45 and duffel.size.x > 0.55, "a duffel lies on its side (%s)" % duffel.size)
	_t._check(TerminalCurb.bag_mesh(3).get_aabb().size.z > carry.size.z, "a carry-on with a backpack leaning on it")
	_t._check(TerminalCurb.bag_mesh(0) == TerminalCurb.bag_mesh(0), "one shared mesh a kind")
	var cart := TerminalCurb.cart_mesh().get_aabb()
	_t._check(cart.size.y > 0.9 and cart.size.y < 1.25 and cart.size.x > 0.9, "a luggage cart is real-sized (%s)" % cart.size)
	var m := TerminalCurb.bag_material()
	_t._check(m.vertex_color_use_as_albedo, "the luggage takes its colour per instance")


func _drop_offs() -> void:
	# Find a car that stops (the decision is a hash of the car and its lap).
	var stopper: Vehicle = null
	var tries: Array = []
	for i in 40:
		var c := Vehicle.new()
		tries.append(c)
		c.traffic = {"loop": 0, "t": 1.0, "speed": 3.0}
		TerminalCurb.loop_speed(c, 0, 3.0, 0.1)
		if float(c.traffic.get("tc_stop", -1.0)) >= 0.0:
			stopper = c
			break
	_t._check(stopper != null, "a share of the kerb lane's cars stop for a drop-off")
	if stopper != null:
		var tr: Dictionary = stopper.traffic
		var stop: float = tr.tc_stop
		_t._check(stop >= TerminalCurb.STOP_T.x and stop <= TerminalCurb.STOP_T.y, "its stop is along the kerb (%.0f m)" % stop)
		# Drive it there.
		var shift := 0.0
		var stood := false
		var gone := false
		var max_shift := 0.0
		var dt := 0.1
		for k in 3000:
			var r: Array = TerminalCurb.loop_speed(stopper, 0, 3.0, dt)
			shift = r[1]
			max_shift = maxf(max_shift, shift)
			if float(r[0]) == 0.0:
				stood = true
			elif stood:
				gone = true
				break
			tr.t = float(tr.t) + float(r[0]) * dt
		_t._check(stood, "it stops at its spot")
		_t._check(max_shift > 1.2 and max_shift <= TerminalCurb.PULL_IN + 0.001, "pulled in toward the kerb (%.2f m)" % max_shift)
		_t._check(gone and not tr.get("hazard", false), "and goes again after its dwell, hazards off")
	for c in tries:
		(c as Vehicle).free()
	var inner := Vehicle.new()
	inner.traffic = {"loop": 1, "t": 60.0}
	var r1: Array = TerminalCurb.loop_speed(inner, 1, 2.5, 0.1)
	_t._check(float(r1[0]) == 2.5 and float(r1[1]) == 0.0, "the inner loop keeps moving")
	inner.free()
	var src := FileAccess.get_file_as_string("res://scripts/npc/traffic.gd")
	_t._check(src.contains("TerminalCurb.loop_speed(car, i, speed, delta)") and src.contains("Vector2(-dir2.y, dir2.x) * float(kerb[1])"),
		"TrafficManager's loop asks the kerb for its speed and shift")


func _cars() -> void:
	var taxis := 0
	var vans := 0
	for i in 60:
		var c := TerminalCurb.loop_car(absi(hash([i, "tc_test"])))
		if c == null:
			continue
		if c.body_type == Vehicle.BodyType.TAXI:
			taxis += 1
		elif c.body_type == Vehicle.BodyType.VAN:
			vans += 1
		c.free()
	_t._check(taxis >= 4 and vans >= 2, "the loop has its taxis (%d) and shuttle vans (%d)" % [taxis, vans])
	_t._check(TerminalCurb.walkers(45) == TerminalCurb.WALKERS, "fewer plain walkers on the kerb with the travellers there")


func _build(city: Node) -> void:
	var macro := _macro(city)
	_t._check(macro != null, "the city's map is there for the kerb's build")
	if macro == null:
		return
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	holder.add_child(body)
	TerminalCurb.build(holder, body, macro, true)
	var names := {}
	for c in holder.get_children():
		names[String(c.name)] = c
	_t._check(names.has("TerminalCurb") and names.has("TerminalCurbSigns") and names.has("TerminalCurbPlates"),
		"the kerb, its lit signs and its plates are laid (%s)" % str(names.keys()))
	var mi := names.get("TerminalCurb") as MeshInstance3D
	_t._check(mi != null and mi.mesh.get_surface_count() >= 5, "one mesh, a surface per material")
	var faces := 0
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
			faces += ((c as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3
	_t._check(faces > 2000, "bollards, pylons, benches and the median collide (%d faces)" % faces)
	var palms := 0
	for c in holder.get_children():
		if String(c.name).contains("palm"):
			palms += 1
	_t._check(palms >= 1, "the median across the lanes is planted with palms")
	holder.free()
	var far := Node3D.new()
	TerminalCurb.build(far, null, macro, false)
	_t._check(far.get_child_count() == 0, "the far copy lays none of it")
	far.free()
	var src := FileAccess.get_file_as_string("res://scripts/world/airport_terminal.gd")
	_t._check(src.contains("TerminalCurb.vestibule(g, x, front, y0, vi)"), "the head house's vestibules are glass")
	var g := LandmarkGeo.new()
	g.use("glass", LandmarkMats.plain("tc_test_g", Color.WHITE))
	g.use("metal", LandmarkMats.plain("tc_test_m", Color.WHITE))
	g.use("dark", LandmarkMats.plain("tc_test_d", Color.WHITE))
	TerminalCurb.vestibule(g, -425.0, 636.0, 0.1, 0)
	var vh := Node3D.new()
	var vm := g.commit(vh, "V")
	_t._check(vm != null and vm.mesh.get_aabb().size.y > 3.3 and vm.mesh.get_aabb().size.y < 4.2, "a vestibule stands its storey")
	vh.free()


func _camera() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w7.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.cameras:
			if c.name == "terminal_curb":
				row = c
	_t._check(not row.is_empty(), "the terminal_curb camera is in cameras_w7.json")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	_t._check(p.y > TerminalCurb.KERB_Z and p.y < TerminalCurb.FRONT_Z and p.x > TerminalCurb.X0 and p.x < TerminalCurb.X1
		and p.y > float(AirportTerminal.ROOF_SECTION[0][0]) and float(row.hour) == 8.0,
		"the camera stands on the kerb under the wing roof at 08:00")
