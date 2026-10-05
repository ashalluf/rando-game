extends RefCounted
## Building sites, house frames and road works (Construction, ConstructionKit, ConstructionWorker,
## HardHat), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after
## the autoloads.
##
## Checks the tables (the shader's copy of the kinds and the crane's jib height), that the plans
## are pure and land where they should (tower sites downtown with a crane that fits, road works in
## a parking lane inside their block, a share of house lots framing), then builds: a FULL chunk with
## a tower site (one site mesh on the construction shader, a crane node on the crane material with
## bounds round its swing, collision, no Building on the lot, the block's other buildings and props
## where they were with Construction off), its LOD build and the far city's capture (the frame, the
## core and the crane with its beacons as far boxes), a chunk with road works (no parked car in the
## closure), a house frame, a worker in hi-vis with a hard hat and a paddle.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	var tower := _find_tower(plan)
	var road := _find_road(plan)
	var house := _find_house(plan)
	_t._check(tower.x != 99999, "a tower site stands within 1.5 km of downtown (%s)" % [tower])
	_t._check(road.x != 99999, "a block near downtown has road works in a parking lane (%s)" % [road])
	_t._check(house.x != 99999, "a suburban block has a house frame going up (%s)" % [house])
	if tower.x != 99999:
		_plan_checks(plan, tower)
		_tower_chunk(city, plan, tower)
		_same_block(city, tower)
		_far(city, plan, tower)
	if road.x != 99999:
		_road_chunk(city, plan, road)
	if house.x != 99999:
		_house_chunk(city, house)
	_worker(city)


func _tables() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/construction.gdshader")
	_t._check(src.contains("%d tinted cab glass" % ConstructionKit.K_CAB_GLASS) and ConstructionKit.KIND_COUNT == ConstructionKit.K_CAB_GLASS + 1
		and ConstructionKit.KIND_COUNT <= 32, "construction.gdshader's header lists every ConstructionKit kind")
	_t._check(src.contains("uniform float jib_y = %s;" % str(ConstructionKit.JIB_Y)), "the crane shader's jib height is ConstructionKit.JIB_Y")
	_t._check(Construction.DEVELOPERS.size() >= 4 and Construction.PROJECTS.size() >= 4, "the sites carry invented developer and project names")


func _find_tower(plan: CityPlan) -> Vector2i:
	var c := plan.block_index_at(Vector2(2800.0, 102.0))
	var best := Vector2i(99999, 99999)
	var best_d := INF
	for ix in range(c.x - 12, c.x + 13):
		for iz in range(c.y - 12, c.y + 13):
			var s := Construction.tower_site(plan, ix, iz)
			if s.is_empty():
				continue
			var d := Vector2(ix - c.x, iz - c.y).length()
			if d < best_d:
				best_d = d
				best = Vector2i(ix, iz)
	return best


func _find_road(plan: CityPlan) -> Vector2i:
	var c := plan.block_index_at(Vector2(2800.0, 102.0))
	for r in 14:
		for ix in range(c.x - r, c.x + r + 1):
			for iz in range(c.y - r, c.y + r + 1):
				if maxi(absi(ix - c.x), absi(iz - c.y)) != r:
					continue
				if not Construction.road_works(plan, ix, iz).is_empty() and Construction.tower_site(plan, ix, iz).is_empty():
					return Vector2i(ix, iz)
	return Vector2i(99999, 99999)


func _find_house(plan: CityPlan) -> Vector2i:
	var c := plan.block_index_at(Vector2(600.0, 1500.0))
	for r in 30:
		for ix in range(c.x - r, c.x + r + 1):
			for iz in range(c.y - r, c.y + r + 1):
				if maxi(absi(ix - c.x), absi(iz - c.y)) != r:
					continue
				var b := plan.block(ix, iz)
				if int(b.district) != CityPlan.District.SUBURBS or int(b.kind) != CityPlan.BlockKind.BUILDINGS or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					continue
				for lot: Dictionary in plan.lots(ix, iz):
					if not lot.yard and Construction.house_site(plan, lot):
						return Vector2i(ix, iz)
	return Vector2i(99999, 99999)


func _plan_checks(plan: CityPlan, k: Vector2i) -> void:
	var s := Construction.tower_site(plan, k.x, k.y)
	Construction._cache.clear()
	var again := Construction.tower_site(plan, k.x, k.y)
	var cell: Rect2 = s.cell
	var foot: Rect2 = s.foot
	var cr: Dictionary = s.crane
	_t._check(int(again.seed) == int(s.seed) and (again.foot as Rect2).is_equal_approx(foot) and float((again.crane as Dictionary).ring) == float(cr.ring),
		"a tower site's plan is pure (the same lot, footprint and crane twice)")
	_t._check(cell.grow(0.01).encloses(foot) and int(s.built) >= 4 and int(s.built) <= int(s.total) and int(s.clad) < int(s.built),
		"the tower stands inside its lot's cell, %d of %d storeys poured, %d clad" % [int(s.built), int(s.total), int(s.clad)])
	var reach := float(cr.jib) + 3.0
	var at: Vector2 = cr.at
	var clear := plan.macro.freeway == null or not plan.macro.freeway.blocks_rect(Rect2(at - Vector2(reach, reach), Vector2(reach * 2.0, reach * 2.0)), 3.0)
	_t._check(clear and float(cr.ring) > float(s.top) + Construction.STOREY and foot.grow(0.01).has_point(at),
		"the crane stands in the tower, its ring %.0f m over a %.0f m frame, its %.0f m swing clear of the freeway" % [float(cr.ring), float(s.top), float(cr.jib)])
	# The planned building there is tall enough to be worth a crane.
	var b := plan.block(k.x, k.y)
	_t._check(int(b.district) in [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN], "tower sites are downtown or in midtown")


func _tower_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var site := chunk.get_node_or_null("ConstructionSite") as MeshInstance3D
	var ground := chunk.get_node_or_null("ConstructionGround") as MeshInstance3D
	_t._check(site != null and site.material_override == ConstructionKit.material() and ground != null
		and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a tower site is one mesh on the construction shader, its ground a shadowless second")
	var cranes := chunk.get_children().filter(func(n: Node) -> bool: return n.is_in_group("tower_crane"))
	var crane_ok := false
	var s := Construction.tower_site(plan, k.x, k.y)
	if cranes.size() == 1:
		var cn := cranes[0] as MeshInstance3D
		var cr: Dictionary = s.crane
		crane_ok = cn.material_override == ConstructionKit.crane_material() and bool(cn.material_override.get_shader_parameter("crane")) \
			and cn.custom_aabb.size.x >= float(cr.jib) * 2.0 and cn.custom_aabb.size.y > float(cr.ring)
	_t._check(crane_ok, "the site has one tower crane on the slewing crane material, its bounds round the whole swing")
	var lights := chunk.get_node_or_null("ConstructionLights") as MeshInstance3D
	_t._check(lights != null and lights.material_override == Construction.lights_material() and lights.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the crane's cathead and the frame's corners carry obstruction lights on the never-shrinking billboard shader")
	_t._check(chunk.get_node_or_null("ConstructionBody") != null and (chunk.get_node("ConstructionBody") as Node).get_child_count() > 10,
		"the frame, the core, the crane's mast and the hoarding have collision")
	# No Building stands on the site's lot.
	var foot: Rect2 = s.foot
	var on_lot := 0
	for c in chunk.get_children():
		if c is Building and foot.has_point(Vector2((c as Node3D).position.x, (c as Node3D).position.z)):
			on_lot += 1
	_t._check(on_lot == 0, "no Building stands on the tower site's lot")
	var crew: Array = (chunk.get_meta("construction") as Dictionary).workers
	var deck := crew.filter(func(w: Dictionary) -> bool: return float(w.lift) > 3.0)
	var gate := crew.filter(func(w: Dictionary) -> bool: return bool(w.paddle))
	_t._check(not deck.is_empty() and not gate.is_empty(), "the site has crew spots on the top deck (%d) and a flagger at the gate" % deck.size())
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## The block built with Construction off has the same other buildings and pavement props.
func _same_block(city: Node3D, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var with := _signature(on)
	on.get_parent().remove_child(on)
	on.free()
	Construction.enabled = false
	Construction._cache.clear()
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	Construction.enabled = true
	Construction._cache.clear()
	var without := _signature(off)
	var none := off.get_node_or_null("ConstructionSite") == null
	off.get_parent().remove_child(off)
	off.free()
	var missing := 0
	for sg: String in with:
		if not without.has(sg):
			missing += 1
	_t._check(none and missing == 0 and without.size() > with.size(),
		"tower block %s built without Construction keeps every other building and prop (%d of %d moved)" % [k, missing, with.size()])


func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building:
			out.append("B %d %.2f %.2f" % [(c as Building).seed, (c as Node3D).position.x, (c as Node3D).position.z])
		elif c is TrashCan:
			out.append("T %.2f %.2f" % [(c as Node3D).position.x, (c as Node3D).position.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	return out


## The LOD build lays no site meshes; it and the far city's capture carry the frame, the core and
## the crane (a mast drawn a pixel wide, beacons) as plant boxes the far city keeps.
func _far(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var none := chunk.get_node_or_null("ConstructionSite") == null and chunk.get_children().filter(func(n: Node) -> bool: return n.is_in_group("tower_crane")).is_empty()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	_t._check(none, "a LOD build of the tower block lays no site mesh or crane node")
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	var customs: Array = boxes.get("custom", [])
	var mast := 0
	var beacon := 0
	var kept := 0
	for c: Color in customs:
		if is_equal_approx(c.a, FarBuilding.PLANT_FLAG) and FarBuilding.far_keeps(c):
			kept += 1
			if int(c.r + 0.5) == FarBuilding.Plant.MAST:
				mast += 1
			elif int(c.r + 0.5) == FarBuilding.Plant.BEACON_MAST:
				beacon += 1
	var s := Construction.tower_site(plan, k.x, k.y)
	_t._check(mast >= 1 and beacon >= 2 and kept >= int(s.built) - int(s.clad) + 4,
		"the far city captures the tower's frame and its crane (%d boxes, the mast, %d beacons)" % [kept, beacon])
	cap.free()


func _road_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var closures: Array = chunk.get_meta("construction_closures", [])
	var blocked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if Construction.blocks_parking(chunk, p):
				blocked += 1
	_t._check(not closures.is_empty() and blocked == 0 and chunk.get_node_or_null("ConstructionSite") != null,
		"road works close a parking lane with no parked car in it (%d closures, %d cars in them)" % [closures.size(), blocked])
	var inside := true
	var rect: Rect2 = plan.block(k.x, k.y).rect
	for c: Dictionary in closures:
		var lo := rect.position.y if int(c.axis) == CityPlan.AXIS_X else rect.position.x
		var hi := rect.end.y if int(c.axis) == CityPlan.AXIS_X else rect.end.x
		var width := plan.road_width(int(c.axis), int(c.index))
		inside = inside and float(c.a) >= lo and float(c.b) <= hi \
			and absf(float(c.lane) - (plan.road_pos(int(c.axis), int(c.index)) + float(c.side) * CityPlan.parking_offset(width))) < 0.01
	_t._check(inside, "every closure stays in its block's stretch of the parking lane")
	var flagger := ((chunk.get_meta("construction") as Dictionary).workers as Array).filter(func(w: Dictionary) -> bool: return bool(w.paddle))
	_t._check(not flagger.is_empty(), "the road works have a flagger with a paddle")
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _house_chunk(city: Node3D, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var ok := chunk.get_node_or_null("ConstructionSite") != null and chunk.get_node_or_null("ConstructionBody") != null
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	_t._check(ok, "suburban block %s builds its house frame (studs, trusses, OSB) with collision" % [k])
	var tris := ConstructionKit.tris
	var plan: CityPlan = city.plan
	var lot := {}
	for l: Dictionary in plan.lots(k.x, k.y):
		if not l.yard and Construction.house_site(plan, l):
			lot = l
			break
	var cap: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	cap.build()
	var none := cap.get_node_or_null("ConstructionSite") == null
	cap.get_parent().remove_child(cap)
	cap.free()
	_t._check(none and not lot.is_empty() and ConstructionKit.tris >= tris, "a LOD build of the frame lays far boxes, no site mesh")


func _worker(city: Node3D) -> void:
	var ped := ConstructionWorker.new()
	ped.setup_vendor(Rect2(-40, -40, 80, 80), 12345, Vector2(5.0, 5.0), 0.0, true, -0.15)
	ped.paddle = true
	ped.position = Vector3(5.0, 0.2, 5.0)
	city.add_child(ped)
	var hat := ped.find_children("HardHat", "MeshInstance3D", true, false)
	var pad := ped.find_children("Paddle", "MeshInstance3D", true, false)
	var hivis := false
	for node in ped.find_children("*", "MeshInstance3D", true, false):
		var m := (node as MeshInstance3D).material_override as ShaderMaterial
		if m and m.get_shader_parameter("cloth_strength") != null and float(m.get_shader_parameter("cloth_strength")) > 0.9:
			hivis = true
	_t._check(hat.size() == 1 and pad.size() == 1 and hivis and ped.is_in_group("pedestrian"),
		"a worker wears hi-vis and a hard hat, holds the paddle, and is a pedestrian like anyone")
	ped.queue_free()
