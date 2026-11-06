extends RefCounted
## The car wash from the kerb (RcCarWash, wave 8 refcam car_wash), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row; the hand-dry rect sits inside the lot in front of the tunnel (empty when
## off); the wet-ground UV2 code and the shader's wet / tunnel branches; a FULL car wash built with
## RcCarWash on has a washed car in its dry area (a real, empty Vehicle) with attendants at it
## holding towels, its queue cars still have drivers; with RC5_CAR_WASH=0 none of it.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_camera_row()
	_rect_and_codes()
	var e := _find_wash(city, plan)
	_t._check(not e.is_empty(), "a car wash was found for the RcCarWash checks")
	if e.is_empty():
		return
	var budget := t.get_node("/root/PhysicsBudget")
	var cap: int = budget.max_active_bodies
	budget.max_active_bodies = 1 << 30
	var keep := RcCarWash.enabled
	RcCarWash.enabled = true
	_full(city, e, true)
	RcCarWash.enabled = false
	_full(city, e, false)
	RcCarWash.enabled = keep
	RcCarWash.apply(RoadsideKit.material())
	budget.max_active_bodies = cap


func _camera_row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "car_wash":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 14.0) and String(row.get("weather", "")) == "clear",
		"the car_wash refcam row is in cameras_w8.json (14:00 clear)")


class FakeSite:
	var w := 46.0
	var d := 22.0


func _rect_and_codes() -> void:
	var keep := RcCarWash.enabled
	var s := FakeSite.new()
	var L := 34.0
	var tunnel := Rect2(s.w * 0.5 - 2.0 - L, s.d * 0.5 - 1.2 - 6.4, L, 6.4)
	RcCarWash.enabled = true
	var r := RcCarWash.dry_rect(s, tunnel)
	var lot := Rect2(-s.w * 0.5, -s.d * 0.5, s.w, s.d)
	_t._check(r.size.x > 10.0 and r.size.y > 6.0 and lot.encloses(r) and r.end.y < tunnel.position.y and r.end.x > tunnel.end.x - 4.0,
		"RcCarWash's hand-dry area is inside the lot, in front of the tunnel at its exit end (%s)" % str(r))
	var u := RcCarWash.wet_u2(0.75)
	RcCarWash.enabled = false
	var off := RcCarWash.dry_rect(s, tunnel)
	var u_off := RcCarWash.wet_u2(0.75)
	RcCarWash.enabled = keep
	_t._check(off.size.x == 0.0 and u.y < -0.1 and u_off.y == 0.0 and u.x == 0.75,
		"with RC5_CAR_WASH=0 there is no dry area and the tunnel floor is the old dry concrete")
	var src := FileAccess.get_file_as_string("res://shaders/roadside.gdshader")
	_t._check(src.contains("float wet = clamp(-metal, 0.0, 1.0);") and src.contains("uniform float wash_look = 0.0;") and src.contains("surf == 6"),
		"roadside.gdshader has the wet concrete (UV2.y < 0) and the tunnel's traced brushes behind wash_look")
	_t._check(RcCarWash.towel_mesh(1).get_surface_count() == 1 and RcCarWash.towel_mesh(1) == RcCarWash.towel_mesh(7),
		"the hand towel mesh is built once per colour")


func _find_wash(city: Node3D, plan: CityPlan) -> Dictionary:
	Roadside.recording = true
	Roadside.record.clear()
	var found := {}
	# The refcam's pad first (seed 1337), then rings round the spawn.
	var order: Array = [plan.block_index_at(Vector2(527.2, -586.8)), plan.block_index_at(Vector2(539.8, -745.7))]
	var k0: Vector2i = plan.block_index_at(Vector2.ZERO)
	for r in 6:
		for bx in range(k0.x - r, k0.x + r + 1):
			for bz in range(k0.y - r, k0.y + r + 1):
				if maxi(absi(bx - k0.x), absi(bz - k0.y)) == r:
					order.append(Vector2i(bx, bz))
	for k: Vector2i in order:
		if not found.is_empty():
			break
		var before := Roadside.record.size()
		var cap := CityChunk.new()
		cap.plan = plan
		cap.ix = k.x
		cap.iz = k.y
		cap.level = CityChunk.Level.LOD
		cap.style = city.chunk_style()
		cap.capturing = true
		cap.build()
		cap.free()
		for i in range(before, Roadside.record.size()):
			var e: Dictionary = Roadside.record[i]
			if int(e.kind) == Roadside.Kind.CAR_WASH and found.is_empty():
				found = e
	Roadside.recording = false
	Roadside.record.clear()
	return found


func _full(city: Node3D, e: Dictionary, on: bool) -> void:
	var chunk: CityChunk = city._new_chunk(e.block, CityChunk.Level.FULL)
	chunk.build()
	var c: Vector2 = e.centre
	var ws := _t.get_node("/root/WorldState")
	var dry_cars: Array = []
	var stall_cars := 0
	var queue_drivers := 0
	var queue_cars := 0
	for v in chunk.get("_cars"):
		if not is_instance_valid(v):
			continue
		var n := v as Node3D
		if String(n.get_meta("car_wash", "")) == "dry":
			dry_cars.append(n)
		elif String(n.get_meta("car_wash", "")) == "stall":
			stall_cars += 1
		elif n.has_meta("roadside") and Vector2(ws.to_world(n.position).x, ws.to_world(n.position).z).distance_to(c) < 30.0:
			queue_cars += 1
			if bool(n.get("_npc_driver")):
				queue_drivers += 1
	var crew: Array = []
	for p in chunk.get_children():
		if (p as Node).is_in_group("car_wash_crew"):
			crew.append(p)
	if on:
		var near := false
		var empty := true
		for car: Node3D in dry_cars:
			var w: Vector3 = ws.to_world(car.position)
			near = near or Vector2(w.x, w.z).distance_to(c) < maxf(float(e.w), float(e.d))
			empty = empty and car.get("driver") == null and not bool(car.get("_npc_driver"))
		_t._check(dry_cars.size() >= 1 and near and empty,
			"a FULL car wash has %d washed car(s) in its hand-dry area, real and empty" % dry_cars.size())
		var held := 0
		var close := 0
		for p: Node3D in crew:
			if p is CarWashAttendant and p.find_child("Towel", true, false) != null:
				held += 1
			for car: Node3D in dry_cars:
				var w: Vector3 = ws.to_world(car.position)
				if Vector2(p.position.x, p.position.z).distance_to(Vector2(w.x, w.z)) < 3.4:
					close += 1
					break
		_t._check(crew.size() >= 2 and held == crew.size() and close >= 1,
			"%d attendants work the dry area, each with a towel (%d with one, %d at a car)" % [crew.size(), held, close])
		_t._check(queue_cars == 0 or queue_drivers == queue_cars,
			"the car wash's queue cars still have drivers (%d of %d)" % [queue_drivers, queue_cars])
	else:
		_t._check(dry_cars.is_empty() and stall_cars == 0 and crew.is_empty(),
			"with RC5_CAR_WASH=0 no washed car, stall Vehicle or attendant is added")
	chunk.retire()
	chunk.queue_free()
