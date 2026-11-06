extends RefCounted
## The elementary school's drop-off at 07:50 (RcSchoolMorning, the school_morning reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row stands on the pavement across from an elementary school's front, 07:50
## clear; the drop-off zone sits beside the bus zone on the same kerb, clear of the block's ends;
## the chunk that owns a -x / -z loading zone parks the school's buses and, at drop-off, the
## parents' cars (driver in, hazards on), which the chunk's own parked cars keep off; the school's
## chunk puts the crossing guard (with the paddle), the supervisor and parents on the pavement; the
## wings' street face gets its sunshades; RC5_SCHOOL_MORNING=0 builds both chunks as before.

var _t: Object
var _was: int = 1


func run(t: Object, city: Node) -> void:
	_t = t
	_was = 1 if RcSchoolMorning.enabled() else 0
	var plan: Variant = city.get("plan")
	if plan == null:
		_t._check(false, "school_morning: the city has a plan")
		return
	var pl := _camera(plan)
	if pl.is_empty():
		return
	_dropoff(pl)
	var budget := city.get_node_or_null("/root/PhysicsBudget")
	var cap: int = int(budget.get("max_active_bodies")) if budget else 0
	if budget:
		budget.set("max_active_bodies", maxi(cap, int(budget.call("active_body_count")) + 200))
	var crowd: int = int(city.get("max_pedestrians"))
	city.set("max_pedestrians", crowd + 60)
	var hour_was := Schools.force_hour
	Schools.force_hour = 7.83
	_kerb(city, plan, pl)
	_front(city, plan, pl)
	_wing()
	Schools.force_hour = hour_was
	city.set("max_pedestrians", crowd)
	if budget:
		budget.set("max_active_bodies", cap)


## The camera row and the school it looks at (its plan), or {}.
func _camera(plan: CityPlan) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (data as Dictionary).get("cameras", []):
		if c.get("name", "") == "school_morning":
			row = c
	_t._check(not row.is_empty() and absf(float(row.get("hour", 0.0)) - 7.83) < 0.01 and row.get("weather", "") == "clear",
		"the school_morning camera row is there, 07:50 clear")
	if row.is_empty():
		return {}
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var pl := {}
	var c := Schools._cell_of(eye)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := Schools.decide(plan, c + Vector2i(dx, dz))
			if not d.is_empty() and not bool(d.high):
				var p := Schools.plan_for_school(plan, d)
				if (p.site as Rect2).grow(40.0).has_point(eye):
					pl = p
	_t._check(not pl.is_empty(), "school_morning looks at an elementary school")
	if pl.is_empty():
		return {}
	var fr: Dictionary = pl.fr
	var d_eye := (eye - (fr.o as Vector2)).dot(fr.d)
	var road: Array = pl.front_road
	var rw := plan.road_width(int(road[0]), int(road[1]))
	# Across the front street: past the far kerb, on its pavement.
	_t._check(d_eye < -(plan.sidewalk_width + rw) and d_eye > -(plan.sidewalk_width * 2.0 + rw),
		"the school_morning eye is on the pavement across the front street (d %.1f)" % d_eye)
	var yaw := deg_to_rad(float(row.eye[3]))
	var look := Vector2(-sin(yaw), -cos(yaw))
	_t._check(look.dot(fr.d) > 0.5, "the camera looks at the school's front")
	return pl


func _dropoff(pl: Dictionary) -> void:
	var r := RcSchoolMorning.dropoff_rect(pl)
	var zr: Rect2 = pl.bus_rect
	var fr: Dictionary = pl.fr
	var lat_r := (r.get_center() - (fr.o as Vector2)).dot(fr.d)
	var lat_z := (zr.get_center() - (fr.o as Vector2)).dot(fr.d)
	var s0 := minf((r.position - (fr.o as Vector2)).dot(fr.s), (r.end - (fr.o as Vector2)).dot(fr.s))
	var s1 := maxf((r.position - (fr.o as Vector2)).dot(fr.s), (r.end - (fr.o as Vector2)).dot(fr.s))
	_t._check(r.size != Vector2.ZERO and not r.intersects(zr) and absf(lat_r - lat_z) < 0.01
		and s0 >= RcSchoolMorning.DROP_END_CLEAR - 0.01 and s1 <= float(fr.A) - RcSchoolMorning.DROP_END_CLEAR + 0.01,
		"the drop-off zone is on the bus zone's kerb, beside it, clear of the block's ends (%s, buses %s)" % [r, zr])
	_t._check(RcSchoolMorning.dropoff_rect(pl) == r, "the drop-off zone is a pure function of the plan")
	var sign := RcSchoolMorning.sign_s(pl, -1.0)
	var bs0 := minf((zr.position - (fr.o as Vector2)).dot(fr.s), (zr.end - (fr.o as Vector2)).dot(fr.s))
	var bs1 := maxf((zr.position - (fr.o as Vector2)).dot(fr.s), (zr.end - (fr.o as Vector2)).dot(fr.s))
	_t._check(sign > 2.9 and sign < float(fr.A) - 2.9 and (sign < bs0 - 2.0 or sign > bs1 + 2.0) and absf(sign - (s0 + s1) * 0.5) < (s1 - s0) * 0.5 + 3.0,
		"the marquee sign stands past the bus zone's end, by the drop-off (s %.1f, buses %.1f..%.1f)" % [sign, bs0, bs1])
	_t._check(RcSchoolMorning.dropoff_time(7.83) and RcSchoolMorning.dropoff_time(15.0) and not RcSchoolMorning.dropoff_time(11.0)
		and not RcSchoolMorning.dropoff_time(21.0), "parents drop off at 07:50 and pick up at 15:00, not at 11:00 or at night")


## The chunk owning the front kerb: buses and parents' cars there, none with the switch off.
func _kerb(city: Node, plan: CityPlan, pl: Dictionary) -> void:
	var spots: Array = Schools.bus_spots(plan, pl)
	var k := plan.chunk_index_at(spots[0][0])
	var drop := RcSchoolMorning.dropoff_rect(pl)
	var school_chunk := false
	for b: Vector2i in pl.blocks:
		if b == k:
			school_chunk = true
	_t._check(not school_chunk, "the school_morning school's loading zone is on a kerb its own chunk does not own (chunk %s)" % k)
	var got := []
	for on in [1, 0]:
		RcSchoolMorning._on = on
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var buses := 0
		var cars := 0
		var lit := 0
		var parked_in := 0
		for c in chunk._cars:
			if not is_instance_valid(c):
				continue
			var v := c as Vehicle
			var p := WorldState.to_world(v.global_position)
			if v.body_type == Vehicle.BodyType.SCHOOL_BUS:
				buses += 1
			elif v.has_meta("school_dropoff"):
				cars += 1
				if v._npc_driver and not v.waiting:
					lit += 1
			elif drop.grow(0.5).has_point(Vector2(p.x, p.z)):
				parked_in += 1
		got.append([buses, cars, lit, parked_in])
		for c in chunk._cars:
			if is_instance_valid(c):
				c.queue_free()
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	RcSchoolMorning._on = _was
	_t._check(int(got[0][0]) == mini(int(pl.buses), spots.size()) and int(got[1][0]) == 0,
		"the kerb's chunk parks the school's buses, and did not before (%s)" % [str(got)])
	_t._check(int(got[0][1]) >= 2 and got[0][2] == got[0][1] and int(got[0][3]) == 0 and int(got[1][1]) == 0,
		"at 07:50 parents' cars stand in the drop-off zone, drivers in, hazards on, no parked car among them (%s)" % [str(got)])


## The school's chunk: the adults on the pavement.
func _front(city: Node, plan: CityPlan, pl: Dictionary) -> void:
	var gate := Vector2.ZERO
	for f: Dictionary in pl.fac:
		if f.t == "lawn":
			gate = Schools._lp(pl.fr, float(f.gate_s), 0.0)
	var k := plan.chunk_index_at(gate)
	var got := []
	for on in [1, 0]:
		RcSchoolMorning._on = on
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var staff := 0
		var guards := 0
		var parents := 0
		for n in chunk.get_children():
			if n is SchoolStaff:
				if (n as SchoolStaff).paddle:
					guards += 1
				elif (n as SchoolStaff).hivis:
					staff += 1
				else:
					parents += 1
		got.append([guards, staff, parents])
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	RcSchoolMorning._on = _was
	_t._check(got[0][0] == 1 and got[0][1] == 1 and int(got[0][2]) >= 2 and got[1] == [0, 0, 0],
		"at drop-off a crossing guard, a supervisor and parents stand at the gate, none with the switch off (%s)" % [str(got)])


## The wing's street face: sunshades, sills and fins (more triangles), none with the switch off.
func _wing() -> void:
	var tris := []
	for on in [1, 0]:
		RcSchoolMorning._on = on
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		SchoolKit.classroom(st, Transform3D(), 40.0, 10.0, 1, Color(0.6, 0.4, 0.3), true, Color(0.1, 0.2, 0.45), false, Color(0.2, 0.3, 0.5))
		tris.append(st.commit().surface_get_array_len(0) / 3)
	RcSchoolMorning._on = _was
	# Four bays of 9 m: four eyebrows (10 triangles) and sills (8), five fins (8).
	_t._check(int(tris[0]) - int(tris[1]) == 4 * 18 + 5 * 8, "the wing's street face gets its sunshades, sills and fins (%s)" % [str(tris)])
	_t._check(RcSchoolMorning.fascia(Color(0.1, 0.2, 0.45)).s < Color(0.1, 0.2, 0.45).s, "the fascia band is weathered paint, less saturated than the swatch")
