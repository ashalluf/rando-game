extends RefCounted
## Hospitals (Hospital, HospitalBuild, HospitalTower, EmergencyCar's TRANSPORT / BACKING / PARKED)
## for tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the
## autoloads. Checks: the placement is pure (the same blocks twice, after a cache clear) and the
## medical centre and a few more hospitals stand on this seed, each block a hospital in
## CityPlan.block() with no lots of its own, outside downtown's 1:1 extent and every landmark; the
## layout keeps its pieces inside the block and apart; a FULL chunk builds the tower (a Building),
## the campus mesh, the EMERGENCY sign, the parked ambulance, the helipad lights and collision
## inside a build budget, and the far city captures the tower's coded boxes and the lit ER panel;
## the drives' kerbs keep parked cars off; an ambulance with a patient aboard goes TRANSPORT to the
## nearest hospital, drives there, backs into a bay facing the street and parks; parked, it goes
## back to the pool.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _ws: Node
var _em: Emergency
var _traffic: TrafficManager


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_ws = _tree.root.get_node("/root/WorldState")
	_em = city.get_node_or_null("Emergency") as Emergency
	_traffic = city.get_node("Traffic") as TrafficManager
	var blocks := _placement()
	if blocks.is_empty():
		return
	_layouts(blocks)
	var med := Hospital.medical_block(_plan)
	_chunk(med if med != Vector2i.MAX else blocks[0])
	_kerbs(blocks[0])
	if _em != null:
		await _transport(med if med != Vector2i.MAX else blocks[0])


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _all_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var med := Hospital.medical_block(_plan)
	if med != Vector2i.MAX:
		out.append(med)
	for cx in range(-5, 6):
		for cz in range(-4, 7):
			var bi := Hospital.cell_block(_plan, Vector2i(cx, cz))
			if bi != Vector2i.MAX:
				out.append(bi)
	return out


func _placement() -> Array[Vector2i]:
	var first := _all_blocks()
	Hospital._cell_cache.clear()
	Hospital._medical_cache.clear()
	Hospital._layout_cache.clear()
	var again := _all_blocks()
	_check(first == again, "hospital placement is pure: the same %d blocks after a cache clear" % first.size())
	_check(Hospital.medical_block(_plan) != Vector2i.MAX, "the medical centre stands near downtown on this seed (%s)" % Hospital.medical_block(_plan))
	_check(first.size() >= 3, "a few hospitals across the map (%d)" % first.size())
	var ok := true
	var why := ""
	for bi in first:
		var b := _plan.block(bi.x, bi.y)
		var rect: Rect2 = b.rect
		if not Hospital.is_hospital(b) or not _plan.lots(bi.x, bi.y).is_empty() or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
			ok = false
			why = "block %s: hospital %s, %d lots" % [bi, b.get("hospital", false), _plan.lots(bi.x, bi.y).size()]
		if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect) or b.has("site"):
			ok = false
			why = "block %s on downtown or a landmark" % bi
	_check(ok, "every hospital block is a hospital in CityPlan.block() with no lots, off downtown and the landmarks %s" % why)
	# A neighbour is untouched: an ordinary block beside the first hospital still has its lots.
	var nb := first[0] + Vector2i(1, 0)
	var nbb := _plan.block(nb.x, nb.y)
	_check(not Hospital.is_hospital(nbb), "the block beside a hospital is not one")
	return first


func _layouts(blocks: Array[Vector2i]) -> void:
	var ok := true
	var why := ""
	for bi in blocks:
		var lay := Hospital.layout(_plan, bi.x, bi.y)
		var area := Rect2(0.0, 0.0, float(lay.W), float(lay.D))
		var podium: Rect2 = lay.podium
		var tower: Rect2 = lay.tower
		var court: Rect2 = lay.court
		var garage: Rect2 = lay.garage
		var lot: Rect2 = lay.lot
		if not area.grow(0.01).encloses(podium) or not area.grow(0.01).encloses(court) or not podium.grow(0.01).encloses(tower):
			ok = false
			why = "%s: podium / court / tower outside" % bi
		if podium.intersects(court.grow(-0.1)):
			ok = false
			why = "%s: podium over the court" % bi
		if garage.size.x > 0.0 and (garage.intersects(podium) or garage.intersects(court) or not area.grow(0.01).encloses(garage)):
			ok = false
			why = "%s: garage overlaps" % bi
		if lot.size.x > 0.0 and (lot.intersects(podium) or lot.intersects(court)):
			ok = false
			why = "%s: lot overlaps" % bi
		for b: Vector2 in lay.bays:
			if not (lay.canopy as Rect2).grow(0.01).has_point(b):
				ok = false
				why = "%s: a bay outside its canopy" % bi
		if float(lay.tower_h) < 20.0 or (bool(lay.medical) and float(lay.tower_h) < 50.0):
			ok = false
			why = "%s: tower %.0f m" % [bi, lay.tower_h]
	_check(ok, "every campus keeps its podium, tower, court, bays, garage and lot inside the block and apart %s" % why)


func _chunk(bi: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var chunk: CityChunk = _city._new_chunk(bi, CityChunk.Level.FULL)
	chunk.build()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var hosp: Node3D = null
	var tower: Building = null
	for n in chunk.get_children():
		if n.is_in_group("hospital"):
			hosp = n
		if n is HospitalTower:
			tower = n
	_check(hosp != null and tower != null and tower.parts.size() == 2,
			"a hospital block's FULL chunk builds the campus and its tower (a Building of %d parts)" % (tower.parts.size() if tower else 0))
	if hosp:
		var names := []
		for n in hosp.get_children():
			names.append(String(n.name))
		var want := ["Campus", "HospitalBody", "ParkedAmbulance", "HelipadLights", "ERSignFace"]
		var missing := want.filter(func(w: String) -> bool: return not names.has(w))
		_check(missing.is_empty(), "it has its campus mesh, collision, parked ambulance, helipad lights and ER sign (missing %s)" % [missing])
		var body := hosp.get_node_or_null("HospitalBody") as StaticBody3D
		_check(body != null and body.get_child_count() > 10 and body.collision_layer == 1 and body.collision_mask == 0,
				"its collision is on the world layer with no mask (%d shapes)" % (body.get_child_count() if body else 0))
	_check(ms < 4000.0, "a hospital chunk builds inside the budget (%.0f ms)" % ms)
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = bi.x
	lod.iz = bi.y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": [], "custom": []})
	var coded := 0
	var panel := 0
	for c: Color in boxes.custom:
		if is_equal_approx(c.a, FarBuilding.PART_FLAG):
			coded += 1
		if is_equal_approx(c.a, FarBuilding.PLANT_FLAG) and int(c.r) == FarBuilding.Plant.PANEL:
			panel += 1
	_check(coded >= 2 and panel >= 1, "the far city captures the tower's coded boxes (%d) and the lit ER panel (%d)" % [coded, panel])
	chunk.queue_free()
	lod.free()


func _kerbs(bi: Vector2i) -> void:
	var lay := Hospital.layout(_plan, bi.x, bi.y)
	var cuts := Hospital.kerb_cuts(_plan, lay)
	var all := true
	for c: Dictionary in cuts:
		if not Hospital.keeps_clear(_plan, c.at):
			all = false
	var far := Hospital.fp(lay, -60.0, -60.0)
	_check(all and not Hospital.keeps_clear(_plan, far), "parked cars keep off the drives' kerbs (%d cuts) and nowhere else" % cuts.size())


## An ambulance with a patient aboard: _finish sends it TRANSPORT to the nearest hospital, it drives
## the lanes there, pulls past the court, backs into a bay nose out and parks.
func _transport(bi: Vector2i) -> void:
	var lay := Hospital.layout(_plan, bi.x, bi.y)
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	var front := Hospital.fp(lay, float(lay.W) * 0.5, -30.0)
	player.global_position = _ws.to_local(Vector3(front.x, _plan.height_at(front) + 1.5, front.y))
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(3)
	var was := _em.enabled
	var scan_was := _em.scan_interval
	_em.enabled = true
	_em.scan_interval = 1e9
	_em._scan_t = 1e9
	_em.clear()
	_traffic.staged = true
	# A call already loaded, on the ER street 70 m up from the court.
	var goal := Hospital.er_goal(lay)
	var start := goal - (lay.n as Vector2) * 70.0 + (lay.a as Vector2) * 8.0
	var inc := _em.open_call(Emergency.KIND_DOWN, Vector3(start.x, _plan.height_at(start), start.y))
	var car := _em.stage(EmergencyCar.Kind.AMBULANCE, inc)
	_check(car != null, "an ambulance stands at a call near the hospital")
	if car == null:
		await _restore(player, home, was, scan_was)
		return
	# The patient aboard, the crew back in: _finish.
	inc.loaded = true
	for c in _em.crews.duplicate():
		if is_instance_valid(c):
			_em.crews.erase(c)
			c.queue_free()
	car.crew_aboard = car.crew_alive
	_em._finish(car)
	_check(car.mode == EmergencyCar.Mode.TRANSPORT and car.hospital.get("block") == lay.block and car.siren_running(),
			"with a patient aboard it goes TRANSPORT to the nearest hospital, siren on (mode %d)" % car.mode)
	var reached := -1
	for i in 3600:
		await _tree.physics_frame
		if car.mode == EmergencyCar.Mode.BACKING and reached < 0:
			reached = i
		if car.mode == EmergencyCar.Mode.PARKED or not is_instance_valid(car):
			break
	_check(is_instance_valid(car) and reached >= 0, "it drives to the ER street and starts backing in (tick %d)" % reached)
	if not is_instance_valid(car):
		await _restore(player, home, was, scan_was)
		return
	var wp: Vector3 = _ws.to_world(car.global_position)
	var bay_ok := car.bay >= 0 and car.bay < 3
	var bay_w := Hospital.fp(lay, ((lay.bays as Array)[maxi(car.bay, 0)] as Vector2).x, ((lay.bays as Array)[maxi(car.bay, 0)] as Vector2).y)
	var fwd := -car.global_basis.z
	var facing := Vector2(fwd.x, fwd.z).normalized().dot(lay.a as Vector2)
	_check(car.mode == EmergencyCar.Mode.PARKED and bay_ok and Vector2(wp.x, wp.z).distance_to(bay_w) < 1.5 and facing > 0.9,
			"it backs into bay %d and parks nose to the street (%.2f m off, facing %.2f, mode %d)" % [car.bay, Vector2(wp.x, wp.z).distance_to(bay_w), facing, car.mode])
	_check(not car.lights_running_emergency() and not car.siren_running(), "parked, its lights and siren are off")
	# Parked long enough and unseen: back to the pool.
	car.parked_t = _em.park_seconds + 1.0
	car.unseen_time = 10.0
	# Nobody looking: the camera turned away from it for the upkeep.
	var cam := _tree.root.get_viewport().get_camera_3d()
	var cam_was := cam.global_transform if cam else Transform3D()
	if cam:
		var away := (cam.global_position - car.global_position).slide(Vector3.UP).normalized()
		cam.global_transform = Transform3D(Basis.looking_at(away if away.length() > 0.1 else Vector3.FORWARD), cam.global_position)
	_em._upkeep(0.5)
	if cam:
		cam.global_transform = cam_was
	_check(not _em.units.has(car), "parked a while unseen, it goes back to the pool")
	await _restore(player, home, was, scan_was)


func _restore(player: Player, home: Vector3, was: bool, scan_was: float) -> void:
	_em.clear()
	_em.enabled = was
	_em.scan_interval = scan_was
	_em._scan_t = 0.0
	_traffic.staged = false
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(3)
