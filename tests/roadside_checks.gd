extends RefCounted
## Roadside commerce (Roadside, RoadsideKit), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Checks the tables (every kind named, sized and rolled; the odds end at 1; no real brand in any
## name), that the pick is a pure hash that always fits its pad and that the city's pads come out
## as every kind; then builds the far city's capture round the spawn to find pads, builds FULL
## chunks holding a gas station and other kinds and checks: one roadside mesh (and one ground mesh)
## on the roadside shader, the dispensers as breakable props, the repeated pieces in rs_* batches
## on the same shader, a night light, the triangle budget, the capture's lod_box and canopy slab;
## and that the block built with Roadside off is the same block (the pad roll and Commercial's two
## rolls are still made, so the buildings and the parked cars after the pad do not move).

## Most triangles one pad may write (the gas station is the heaviest; the shells and dispensers'
## batches come on top, shared by the chunk).
const PAD_TRIS := 26000
const BRANDS := ["SHELL", "CHEVRON", "ARCO", "MOBIL", "TEXACO", "VALERO", "EXXON", "UNION 76", "SINCLAIR", "CIRCLE K",
	"MCDONALD", "WENDY", "TACO BELL", "IN-N-OUT", "JACK IN", "CARL'S", "RANDY", "STARBUCKS", "DUNKIN", "DENNY",
	"NORMS", "JIFFY", "PEP BOYS", "FIRESTONE", "GOODYEAR", "MIDAS", "MEINEKE", "BIG O", "DISCOUNT TIRE", "SPEEDWAY",
	"7-ELEVEN", "AM/PM", "AMPM", "GOOGIES", "PANN", "JOHNIE", "BOB'S BIG BOY", "KRISPY", "WINCHELL"]

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	_picks(plan)
	var pads := _capture(city, plan)
	# The A/B compares parked cars, which PhysicsBudget caps city-wide: late in the smoke test the
	# city is near that cap, and the OFF build (made while the ON chunk's cars are still queued for
	# freeing) would get fewer. Lift the cap for the checks' own builds.
	var budget := t.get_node("/root/PhysicsBudget")
	var cap: int = budget.max_active_bodies
	budget.max_active_bodies = 1 << 30
	var kinds := {}
	for e: Dictionary in pads:
		kinds[int(e.kind)] = true
	_t._check(kinds.size() >= 4, "the pads round the spawn come out as %d of the six roadside kinds" % kinds.size())
	# Build the FULL chunks of pads until a gas station and two other kinds have been seen.
	var seen := {}
	var tried := 0
	for e: Dictionary in pads:
		if seen.size() >= 3 and seen.has(Roadside.Kind.GAS):
			break
		if seen.has(int(e.kind)) or tried >= 10:
			continue
		tried += 1
		_full(city, plan, e, seen)
	_t._check(seen.has(Roadside.Kind.GAS), "a gas station was built at FULL and checked (%d pads tried)" % tried)
	budget.max_active_bodies = cap


func _tables() -> void:
	var ok: bool = Roadside.KIND_NAMES.size() == Roadside.Kind.size() and Roadside.MIN_SIZE.size() == Roadside.Kind.size()
	var last := 0.0
	for o: Array in Roadside.ODDS:
		ok = ok and float(o[1]) > last
		last = float(o[1])
	_t._check(ok and is_equal_approx(last, 1.0) and Roadside.ODDS.size() == Roadside.Kind.size(),
		"every roadside kind is named, sized and rolled, and the odds run to 1")
	var names: Array = []
	for b: Array in Roadside.GAS_BRANDS:
		names.append(b[0])
	names.append_array(Roadside.STORE_NAMES)
	names.append_array(Roadside.WASH_NAMES)
	for a: Array in Roadside.AUTO_NAMES:
		names.append_array(a)
	names.append_array(Roadside.DINER_NAMES)
	for a: Array in Roadside.STAND_NAMES:
		names.append(a[0])
	names.append_array(Roadside.FAST_NAMES)
	var hits: Array = []
	for n: String in names:
		for b: String in BRANDS:
			if n.to_upper().contains(b):
				hits.append(n)
	_t._check(hits.is_empty(), "no roadside name is a real brand's (%s)" % str(hits))
	# Every piece of the kit is built and on the roadside shader.
	var mats := true
	for m: Mesh in [RoadsideKit.dispenser(), RoadsideKit.vacuum(), RoadsideKit.tyre(), RoadsideKit.menu_board(),
			RoadsideKit.speaker_post(), RoadsideKit.air_machine(), RoadsideKit.ice_chest(), RoadsideKit.propane_cage(),
			RoadsideKit.service_stand(), RoadsideKit.lift()]:
		mats = mats and m != null and m.get_surface_count() == 1 and m.surface_get_material(0) == RoadsideKit.material()
	_t._check(mats, "every roadside kit piece is one surface on the roadside shader")


## The pick is a pure hash of seed + lot and always fits its pad.
func _picks(plan: CityPlan) -> void:
	var same := true
	var fits := true
	var counts := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 600:
		var lot := {"center": Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0)), "size": Vector2.ZERO}
		var w := rng.randf_range(18.0, 46.0)
		var d := rng.randf_range(18.0, 46.0)
		var fast := rng.randf() < 0.55
		var k := Roadside.kind_for(plan, lot, w, d, fast)
		same = same and k == Roadside.kind_for(plan, lot, w, d, fast)
		var m: Vector2 = Roadside.MIN_SIZE[k]
		fits = fits and w >= m.x and d >= m.y
		counts[k] = int(counts.get(k, 0)) + 1
	_t._check(same, "a pad's kind is a pure function of seed, lot and size")
	_t._check(fits, "a pad is only ever given a kind it is big enough for")
	_t._check(counts.size() == Roadside.Kind.size(), "pads of every size come out as all six kinds (%s)" % str(counts))


## The far city's capture of the blocks round the spawn, recording every pad.
func _capture(city: Node3D, plan: CityPlan) -> Array:
	Roadside.recording = true
	Roadside.record.clear()
	var k0: Vector2i = plan.block_index_at(Vector2.ZERO)
	var lod_boxes := 0
	for bx in range(k0.x - 6, k0.x + 7):
		for bz in range(k0.y - 6, k0.y + 7):
			var before := Roadside.record.size()
			var cap := CityChunk.new()
			cap.plan = plan
			cap.ix = bx
			cap.iz = bz
			cap.level = CityChunk.Level.LOD
			cap.style = city.chunk_style()
			cap.capturing = true
			cap.build()
			if Roadside.record.size() > before:
				var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
				lod_boxes += (boxes.get("xforms", []) as Array).size()
			cap.free()
	Roadside.recording = false
	var pads := Roadside.record.duplicate()
	_t._check(pads.size() >= 10 and lod_boxes >= pads.size(), "the far city captures the pads round the spawn as lod_boxes (%d pads, %d boxes in their blocks)" % [pads.size(), lod_boxes])
	return pads


func _full(city: Node3D, plan: CityPlan, e: Dictionary, seen: Dictionary) -> void:
	var k: Vector2i = e.block
	Roadside.recording = true
	Roadside.record.clear()
	Roadside.built_tris = 0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	Roadside.recording = false
	var built: Array = Roadside.record.duplicate()
	var tris := Roadside.built_tris
	Roadside.record = built
	if built.is_empty():
		_drop(chunk)
		return
	var mesh: MeshInstance3D = null
	var ground: MeshInstance3D = null
	var rs_ok := true
	var lights := 0
	for c in chunk.get_children():
		if c.name == "Roadside":
			mesh = c
		elif c.name == "RoadsideGround":
			ground = c
		elif c is MultiMeshInstance3D and String(c.name).begins_with("Batch_rs_") and String(c.name) != "Batch_rs_pool":
			rs_ok = rs_ok and (c as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) == RoadsideKit.material()
		elif c.name == "RoadsideLights":
			for l in c.get_children():
				if l is OmniLight3D and (l as Node).is_in_group("lamp_light"):
					lights += 1
	var kinds := []
	for b: Dictionary in built:
		kinds.append(Roadside.KIND_NAMES[int(b.kind)])
		seen[int(b.kind)] = true
	_t._check(mesh != null and mesh.material_override == RoadsideKit.material() and ground != null
		and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and rs_ok,
		"a FULL chunk's pads (%s) are one roadside mesh and one shadowless ground mesh, their pieces rs_ batches, all on the roadside shader" % ", ".join(kinds))
	_t._check(tris > 1000 and tris < PAD_TRIS * built.size(), "the chunk's %d pad(s) write %d triangles (budget %d a pad)" % [built.size(), tris, PAD_TRIS])
	_t._check(OS.has_feature("web") or lights >= built.size(), "every pad lights its forecourt after dark (%d lamp_light)" % lights)
	# Queued cars (the car wash's lane, the drive-thru's loop) are real parked Vehicles with a
	# driver in and the brake lamps on, no hazards.
	var queued := 0
	var waiting_ok := true
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and (car as Node).has_meta("roadside"):
			queued += 1
			waiting_ok = waiting_ok and car.waiting and car.light_brake and car.light_signal == 0 and car._cabin_seats() != 0
	var wash := false
	for b: Dictionary in built:
		wash = wash or int(b.kind) == Roadside.Kind.CAR_WASH
	if wash or queued > 0:
		_t._check((queued > 0 or not wash) and waiting_ok, "the pads' queued cars are parked Vehicles with a driver seated, brake lamps on, no hazards (%d)" % queued)
	var gas := false
	for b: Dictionary in built:
		gas = gas or int(b.kind) == Roadside.Kind.GAS
	if gas:
		var pumps := 0
		for r: Dictionary in chunk.prop_records:
			if String(r.kind) == "pump" and not (r.shapes as Array).is_empty():
				pumps += 1
		_t._check(pumps >= 2, "the gas station's dispensers are breakable props with collision (%d)" % pumps)
	# The same block with Roadside off: the buildings and parked cars after the pad do not move.
	var a := _layout(chunk)
	_drop(chunk)
	Roadside.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	Roadside.enabled = true
	var b2 := _layout(off)
	_drop(off)
	_t._check(a == b2, "the block built with Roadside off has the same buildings and parked cars (%d / %d)%s" % [(a[0] as Array).size(), (a[1] as Array).size(), _first_diff(a, b2)])


func _drop(chunk: CityChunk) -> void:
	chunk.retire()
	chunk.queue_free()


## The block's buildings (seed and place) and its street-parked cars (place), for the A/B.
func _layout(chunk: CityChunk) -> Array:
	var blds: Array = []
	for c in chunk.get_children():
		if c is Building:
			blds.append([(c as Building).seed, (c as Node3D).position.snapped(Vector3.ONE * 0.01)])
	var cars: Array = []
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and not (car as Node).is_queued_for_deletion() and not (car as Node).has_meta("roadside"):
			cars.append((car as Node3D).global_position.snapped(Vector3.ONE * 0.01) if (car as Node).is_inside_tree() else (car as Node3D).position.snapped(Vector3.ONE * 0.01))
	return [blds, cars]


## The first building or car that differs between two layouts, for the A/B's label ("" if none).
func _first_diff(a: Array, b: Array) -> String:
	for i in 2:
		var x: Array = a[i]
		var y: Array = b[i]
		for j in maxi(x.size(), y.size()):
			var u = x[j] if j < x.size() else null
			var v = y[j] if j < y.size() else null
			if u != v:
				return ": %s %d on %s, off %s" % ["building" if i == 0 else "car", j, str(u), str(v)]
	return ""
