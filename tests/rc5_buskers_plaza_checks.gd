extends RefCounted
## The buskers' plaza (Rc5Buskers, the buskers_plaza reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row (its staging key, the eye on a PLAZA block); a plaza rolls three pitches
## with slots 0 and 1 exactly as before and the third beside the first; staging forces a slot's
## kind whatever the odds and the hour; a plaza chunk built at 15:30 lays its acts' gear on the
## paving (not under it), the fountain as a smooth basin, a pool and jets, the breakdancer's outer
## ring of spots and the plaza's open-ground walkers; an act's people come even when the crowd cap
## is spent; RC5_BUSKERS=0 is the plaza as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	var was := Rc5Buskers.enabled
	var was_plaza := Rc5Buskers.stage_plaza
	var was_hour := Buskers.force_hour
	Rc5Buskers.enabled = true
	Rc5Buskers.stage_plaza = []
	var k := _camera(plan)
	_slots(plan, k)
	if k.x != 99999:
		_chunk(city, plan, k)
	Rc5Buskers.enabled = false
	Rc5Buskers.stage_plaza = []
	_t._check(Rc5Buskers.plaza_slots() == 2 and Rc5Buskers.gear_lift(-1) == 0.0 and not Rc5Buskers.reserve_room(),
		"RC5_BUSKERS=0: two pitches a plaza, the gear and the crowd cap as before")
	Rc5Buskers.enabled = was
	Rc5Buskers.stage_plaza = was_plaza
	Buskers.force_hour = was_hour


## The row: on a PLAZA block, staged with the three acts the task names.
func _camera(plan: CityPlan) -> Vector2i:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var row: Dictionary = {}
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for c: Dictionary in (data as Dictionary).get("cameras", []):
				if String(c.get("name", "")) == "buskers_plaza":
					row = c
	var ok := not row.is_empty() and String(row.get("busk_plaza", "")) == "break,statue,mariachi" \
		and absf(float(row.get("hour", 0.0)) - 15.5) < 0.01
	var k := Vector2i(99999, 99999)
	if ok:
		var eye: Array = row.eye
		var b := plan.block_index_at(Vector2(float(eye[0]), float(eye[2])))
		ok = int(plan.block(b.x, b.y).get("kind", -1)) == CityPlan.BlockKind.PLAZA
		k = b
	_t._check(ok, "the buskers_plaza camera stands on a downtown PLAZA block at 15:30, staged with the breakdancers, the statue and the mariachis")
	return k


func _slots(plan: CityPlan, k: Vector2i) -> void:
	# Over the plazas round the camera: three slots, slots 0 and 1 as with two.
	var same := true
	var thirds := 0
	var plazas := 0
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			var ix := k.x + dx if k.x != 99999 else dx
			var iz := k.y + dz if k.y != 99999 else dz
			var block := plan.block(ix, iz)
			if not Buskers._is_plaza(block):
				continue
			plazas += 1
			Rc5Buskers.enabled = true
			var three := Buskers.plan_block(plan, ix, iz, 15.0)
			Rc5Buskers.enabled = false
			var two := Buskers.plan_block(plan, ix, iz, 15.0)
			Rc5Buskers.enabled = true
			var first := three.filter(func(v: Dictionary) -> bool: return int(v.slot) < 2)
			same = same and first.size() == two.size()
			for i in mini(first.size(), two.size()):
				same = same and int(first[i].kind) == int(two[i].kind) and String(first[i].id) == String(two[i].id)
			thirds += three.filter(func(v: Dictionary) -> bool: return int(v.slot) == 2).size()
	_t._check(plazas > 0 and same and thirds > 0,
		"a plaza rolls a third pitch and its first two exactly as before (%d plazas, %d third acts at 15:00)" % [plazas, thirds])
	var d := Rc5Buskers.slot_side(plan.seed, 3, 4, 2, false)
	_t._check(absf(d.y) < 0.001 and absf(absf(d.x) - Rc5Buskers.SIDE_STEP) < 0.001 and Rc5Buskers.slot_dir(plan.seed, 3, 4, 2, false) == Vector2(0, 1)
		and Rc5Buskers.slot_side(plan.seed, 3, 4, 0, false) == Vector2.ZERO and Rc5Buskers.slot_dir(plan.seed, 3, 4, 1, false) == Vector2(0, -1),
		"the third pitch stands beside the first, at the same end of the square")
	# Staged: the kinds forced, at 04:00 too (no act works then).
	if k.x != 99999:
		Rc5Buskers.stage_plaza = Rc5Buskers._kinds("break,statue,mariachi")
		var acts := Buskers.plan_block(plan, k.x, k.y, 4.0)
		var kinds := acts.map(func(v: Dictionary) -> int: return int(v.kind))
		_t._check(kinds == [Buskers.Kind.BREAK, Buskers.Kind.STATUE, Buskers.Kind.MARIACHI],
			"BUSK_PLAZA forces a plaza's three pitches whatever the odds and the hour (%s)" % str(kinds))
		_t._check(Rc5Buskers._kinds("none").is_empty(), "BUSK_PLAZA=none stages nothing")


func _chunk(city: Node, plan: CityPlan, k: Vector2i) -> void:
	Buskers.force_hour = 15.5
	Rc5Buskers.stage_plaza = Rc5Buskers._kinds("break,statue,mariachi")
	var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
	chunk.build()
	var acts: Array = chunk.get_meta("busk_acts", [])
	_t._check(acts.size() == 3, "the staged plaza lays three acts (%d)" % acts.size())
	# The gear stands on the paving (4 cm up), not under it.
	var lifted := false
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_busk_break":
			var mm := (c as MultiMeshInstance3D).multimesh
			if mm.instance_count > 0:
				var y := mm.get_instance_transform(0).origin.y
				# Headless returns identity for instance transforms; the batch's own data says it.
				lifted = y == 0.0 or y > CityChunk.SIDEWALK_TOP + 0.03
	_t._check(lifted, "the breakdancer's cardboard lies on the plaza's paving, not under it")
	var pool := chunk.find_child("PlazaPool", false, false)
	var jets := chunk.find_child("PlazaJets", false, false)
	var basin := chunk.find_child("PlazaBasin", false, false)
	_t._check(pool != null and jets != null and basin != null and (basin as MeshInstance3D).mesh.get_surface_count() == 1,
		"the plaza's fountain is a smooth basin with a pool and jets")
	var ring := 0
	for q: Dictionary in chunk.get_meta("vendor_queue", []):
		if q.record is Dictionary and String((q.record as Dictionary).get("busk", "")).ends_with("_0"):
			ring += 1
	_t._check(ring >= Rc5Buskers.RING_SPOTS, "passers-by can join the breakdancers' ring (%d spots)" % ring)
	var trio: Array = []
	for sp: Dictionary in chunk.get_meta("busk_people", []):
		if bool(sp.busker) and int(sp.kind) == Buskers.Kind.MARIACHI:
			trio.append(Rc5Buskers.rig_of(int(sp.seed)))
	var distinct: bool = trio.size() == 3 and trio[0] != trio[1] and trio[1] != trio[2] and trio[0] != trio[2]
	_t._check(distinct and trio.all(func(r: String) -> bool: return r in Buskers.RIGS[Buskers.Kind.MARIACHI]),
		"the mariachi trio are three different people of the trio's rigs (%s)" % str(trio))
	var rects: Array = chunk.get_meta("plaza_rects", [])
	_t._check(not rects.is_empty(), "the plaza's open ground has walkers of its own")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# A spent crowd cap: an act's people come all the same.
	var holder := _Full.new()
	city.add_child(holder)
	holder.set_meta("busk_people", [{"busker": true, "kind": Buskers.Kind.STATUE, "role": 0, "at": Vector2(3, 0),
		"yaw": 0.0, "seed": Buskers.seed_for(5, Buskers.RIGS[Buskers.Kind.STATUE]), "rect": Rect2(-20, -10, 40, 20), "id": "busk_t"}])
	Buskers.spawn_person(holder, 0)
	var came := holder.get_children().size() == 1
	Rc5Buskers.enabled = false
	holder.set_meta("busk_live", {})
	Buskers.spawn_person(holder, 0)
	var refused := holder.get_children().size() == 1
	Rc5Buskers.enabled = true
	_t._check(came and refused, "a performer comes though the crowd cap is spent (refused with RC5_BUSKERS=0)")
	holder.queue_free()
	Buskers.force_hour = -1.0


class _Full:
	extends CityChunk

	func ground_y(_x: float, _z: float) -> float:
		return 0.2

	func _take_crowd_room(_r: float = 0.0) -> bool:
		return false
