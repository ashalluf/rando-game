extends RefCounted
## The auto row refcam (RcAutoRow, wave 8 refcam auto_row), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row; the windscreen measure finds the glass of a code-built car profile
## (bonnet, raked screen, roof) and lays a card on it; the body type a box kind stands in for is
## pure; a FULL chunk of a new-car dealer moves every box car into the per-cell groups (box past
## REAL_NEAR, the real body within it, as many as there were box cars) and drops the kerb trees in
## front of its frontage; with RcAutoRow off the chunk has none of it.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_camera_row()
	_measure()
	var same := true
	for v in 4:
		same = same and RcAutoRow.body_type(plan.seed, v, Vector3(931.4, 0.0, 451.0)) == RcAutoRow.body_type(plan.seed, v, Vector3(931.4, 0.0, 451.0))
		same = same and (RcAutoRow.TYPES[v] as Array).has(RcAutoRow.body_type(plan.seed, v, Vector3(10.0 * v, 0.0, 3.0)))
	_t._check(same, "a lot car's body type is a hash of the stall from its box kind's list")
	var k := Vector2i(99999, 0)
	for ix in range(-14, 15):
		for iz in range(-16, 17):
			var s := CarDealers.site(plan, ix, iz)
			if not s.is_empty() and not s.used and float((s.frame as Dictionary).len) >= 40.0:
				k = Vector2i(ix, iz)
				break
		if k.x != 99999:
			break
	_t._check(k.x != 99999, "a new-car dealer was found round the start for the RcAutoRow checks")
	if k.x == 99999:
		return
	var budget: Node = t.get_tree().root.get_node_or_null("PhysicsBudget")
	var cap: int = int(budget.get("max_active_bodies")) if budget else 0
	if budget:
		budget.set("max_active_bodies", maxi(cap, int(budget.call("active_body_count")) + 200))
	var on := _chunk(city, plan, k)
	RcAutoRow.enabled = false
	var off := _chunk(city, plan, k)
	RcAutoRow.enabled = true
	if budget:
		budget.set("max_active_bodies", cap)
	var real_ok: bool = CarParkBuild.real_body(Vehicle.BodyType.SEDAN).has("mesh")
	_t._check(int(on.box) == int(on.cars) and int(on.cars) > 0 and (not real_ok or int(on.real) == int(on.cars)),
		"every dealer lot car is drawn per cell: the box past %d m, the real body within it (%d cars, %d boxes, %d real)" % [RcAutoRow.REAL_NEAR, on.cars, on.box, on.real])
	_t._check(int(on.hits) == int(off.hits) and int(on.dropped) == int(on.hits) and int(off.dropped) == 0,
		"no street tree stands on the dealer's frontage (%d dropped; with RcAutoRow off all %d planted, rolls unmoved)" % [on.dropped, off.hits])
	_t._check(int(off.box) == 0 and int(off.real) == 0 and int(off.cars) == int(on.cars),
		"with RcAutoRow off the lot keeps its box cars in the batch (the A/B)")


func _camera_row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "auto_row":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 11.0) and String(row.get("weather", "")) == "clear",
		"the auto_row refcam row is in cameras_w8.json (11:00 clear)")


## A car's profile built from faces (no renderer needed): a bonnet at 0.95 m from the nose to
## 1.6 m back, a screen raked up to the roof at 1.45 m by 2.5 m back, the roof to the tail.
func _measure() -> void:
	var f := PackedVector3Array()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		f.append_array([a, b, c, a, c, d])
	var w := 0.9
	quad.call(Vector3(-w, 0.95, -2.3), Vector3(w, 0.95, -2.3), Vector3(w, 0.95, -0.7), Vector3(-w, 0.95, -0.7))
	quad.call(Vector3(-w, 0.95, -0.7), Vector3(w, 0.95, -0.7), Vector3(w, 1.45, 0.2), Vector3(-w, 1.45, 0.2))
	quad.call(Vector3(-w, 1.45, 0.2), Vector3(w, 1.45, 0.2), Vector3(w, 1.45, 2.3), Vector3(-w, 1.45, 2.3))
	var tm := TriangleMesh.new()
	var made := tm.create_from_faces(f)
	var sc: Dictionary = RcAutoRow._measure([[tm, Transform3D()]]) if made else {}
	var ok := not sc.is_empty()
	if ok:
		var up: Vector3 = sc.up
		var base: Vector3 = sc.base
		var slope := Vector3(0.0, 0.5, 0.9).normalized()
		ok = up.dot(slope) > 0.98 and base.z > -0.8 and base.z < -0.3 and base.y > 0.95 and base.y < 1.1
		var card := RcAutoRow.card_xform(sc, false)
		# The card lies on the glass: its centre a little off the screen's plane, its normal the screen's.
		var p := card.origin
		var on_glass := (p - Vector3(p.x, 0.95, -0.7)).dot(Vector3(0.0, 0.9, -0.5).normalized())
		ok = ok and on_glass > 0.005 and on_glass < 0.03 and card.basis.z.normalized().dot(Vector3(0.0, 0.9, -0.5).normalized()) > 0.98
	_t._check(ok, "the windscreen measure finds a raked screen between bonnet and roof and lays the card on it (%s)" % str(sc))


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> Dictionary:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var hits := RcAutoRow.band_hits
	var dropped := RcAutoRow.dropped
	chunk.build()
	var out := {"cars": 0, "box": 0, "real": 0, "hits": RcAutoRow.band_hits - hits, "dropped": RcAutoRow.dropped - dropped}
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "dealer_car":
			out.cars += 1
	for c in chunk.get_children():
		if c is MultiMeshInstance3D:
			var n := String(c.name)
			var count: int = (c as MultiMeshInstance3D).multimesh.instance_count
			if n.begins_with("DealerBoxCars"):
				out.box += count
			elif n.begins_with("DealerRealCars"):
				out.real += count
	chunk.get_parent().remove_child(chunk)
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).free()
	chunk.get("_cars").clear()
	chunk.free()
	return out

