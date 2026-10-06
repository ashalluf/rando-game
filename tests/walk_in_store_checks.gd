extends RefCounted
## The corner store you can walk into (CornerStore, CornerStoreKit, CornerStoreSite) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the placement is pure (the same answer twice) and there are stores in MIDTOWN and the
## SUBURBS; a store stands on its block's corner lot, inside the pavement, faces an open street,
## claims exactly that lot and no other feature's; the switch turns it off; a FULL chunk builds
## the shell, the traced glass, the door, the collision, then the interior, the goods and the
## lights in its deferred steps, inside their budgets, all hidden; walking up shows the interior
## behind clear glass and the door swings in; walking away hides it again; the LOD capture sees a
## box and a lit sign panel; and every other building of the block stands where it stood with the
## store off.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	var t0 := Time.get_ticks_msec()
	var all := _pure()
	if all.is_empty():
		return
	await _chunk(all[0])
	_lod(all[0])
	_unmoved(all[0])
	print("WALK_IN_STORE_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _pure() -> Array:
	var all := CornerStore.near(_plan, Vector2(600.0, 0.0), 4200.0)
	var districts := {}
	for s: Dictionary in all:
		districts[int(s.district)] = true
	_check(all.size() >= 10 and districts.has(CityPlan.District.MIDTOWN) and districts.has(CityPlan.District.SUBURBS),
			"corner stores stand in midtown and the suburbs (%d, districts %s)" % [all.size(), districts.keys()])
	if all.is_empty():
		return []
	var s: Dictionary = all[0]
	var bi: Vector2i = s.block
	CornerStore._cache.erase(Vector3i(_plan.seed, bi.x, bi.y))
	var again := CornerStore.plan_for(_plan, bi.x, bi.y)
	_check(not again.is_empty() and int(again.lot) == int(s.lot) and String(again.name) == String(s.name) and (again.rect as Rect2) == (s.rect as Rect2),
			"a corner store is worked out the same way twice (%s)" % s.name)
	var bad := 0
	var names := {}
	for st: Dictionary in all:
		names[String(st.name)] = true
		var b2: Vector2i = st.block
		var blk := _plan.block(b2.x, b2.y)
		var inner := (blk.rect as Rect2).grow(-_plan.sidewalk_width + 0.05)
		var fp: Rect2 = st.rect
		var claimed := 0
		var corner_ok := false
		for lot: Dictionary in _plan.lots(b2.x, b2.y):
			if CornerStore.claims(_plan, b2.x, b2.y, lot):
				claimed += 1
				corner_ok = (lot.cell as Rect2).grow(0.05).encloses(fp)
			if int(lot.seed) == int(st.lot) and (FireStation.claims(_plan, b2.x, b2.y, lot) or CivicBuildings.claims(_plan, b2.x, b2.y, lot)
					or PoliceStation.claims(_plan, b2.x, b2.y, lot) or Worship.claims(_plan, b2.x, b2.y, lot)):
				claimed += 10
		var f: Vector2 = st.front
		var o: Vector2 = st.origin
		var road_open := true
		var axis := CityPlan.AXIS_X if absf(f.x) > 0.5 else CityPlan.AXIS_Z
		var idx := (b2.x if f.x < 0.0 else b2.x + 1) if axis == CityPlan.AXIS_X else (b2.y if f.y < 0.0 else b2.y + 1)
		road_open = _plan.road_open(axis, idx, o.y if axis == CityPlan.AXIS_X else o.x)
		if not inner.encloses(fp) or claimed != 1 or not corner_ok or not road_open:
			bad += 1
			if bad <= 3:
				print("walk-in store: bad %s at %s inner %s fp %s claimed %d corner %s road %s" % [st.name, b2, inner, fp, claimed, corner_ok, road_open])
		if not [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS].has(int(st.district)):
			bad += 1
	_check(bad == 0, "every store is its block's corner lot, inside the pavement, on an open street, nobody else's (%d bad of %d)" % [bad, all.size()])
	_check(names.size() >= 6, "the stores carry many names (%d)" % names.size())
	CornerStore.enabled = false
	CornerStore._cache.clear()
	var off := CornerStore.plan_for(_plan, bi.x, bi.y)
	CornerStore.enabled = true
	CornerStore._cache.clear()
	_check(off.is_empty(), "WALK_IN_STORE=0 builds no store")
	return CornerStore.near(_plan, Vector2(600.0, 0.0), 4200.0)


func _site_in(chunk: Node) -> CornerStoreSite:
	for n in chunk.get_children():
		if n is CornerStoreSite:
			return n
	return null


func _chunk(s: Dictionary) -> void:
	var chunk: CityChunk = _city._new_chunk(s.block, CityChunk.Level.FULL)
	chunk.position = -WorldState.world_offset
	var bt := Time.get_ticks_usec()
	chunk.build()
	var build_ms := float(Time.get_ticks_usec() - bt) / 1000.0
	var site := _site_in(chunk)
	_check(site != null, "the store's chunk builds it (%s, chunk %.0f ms)" % [s.name, build_ms])
	if site == null:
		chunk.queue_free()
		return
	site.set_process(false)
	var parts := ["Shell", "Glass", "Frames", "Door", "Body", "Interior"]
	var missing: Array = []
	for p: String in parts:
		if not site.has_node(p):
			missing.append(p)
	var shapes := 0
	for c in site.get_node("Body").get_children():
		if c is CollisionShape3D:
			shapes += 1
	_check(missing.is_empty() and shapes >= 12 and site.get_node("Door").has_node("DoorBody"),
			"the shell, glass, frames, door and collision are there (missing %s, %d shapes)" % [missing, shapes])
	var shell := (site.get_node("Shell") as MeshInstance3D).mesh
	var stris := 0
	for si in shell.get_surface_count():
		stris += shell.surface_get_array_len(si) / 3
	var glass := site.get_node("Glass") as GeometryInstance3D
	var traced := glass.material_override as ShaderMaterial
	_check(stris > 1500 and stris < 40000 and traced != null and traced.shader.resource_path.ends_with("corner_store_glass.gdshader"),
			"the outside is real geometry inside its budget with the traced room on the glass (%d triangles)" % stris)
	var interior := site.get_node("Interior") as Node3D
	var goods := 0
	var kinds := 0
	var lights := 0
	for c in interior.get_children():
		if c is MultiMeshInstance3D:
			goods += (c as MultiMeshInstance3D).multimesh.instance_count
			kinds += 1
		elif c is OmniLight3D:
			lights += 1
	_check(site.interior_ready and interior.has_node("Room") and kinds >= 3 and goods >= 400 and goods <= 6000 and lights >= 1,
			"the interior is built: the room, %d goods of %d kinds, %d lights (room %d triangles)" % [goods, kinds, lights, CornerStoreKit.last_interior_tris])
	_check(CornerStoreKit.last_interior_tris > 1000 and CornerStoreKit.last_interior_tris < 60000,
			"the room's fittings are inside their budget (%d triangles)" % CornerStoreKit.last_interior_tris)
	_check(not interior.visible and not site.shown, "the interior is hidden while nobody is near")
	# Walking up: the camera at the window, then the player at the door.
	var W: float = s.W
	var D: float = s.D
	var lay: Dictionary = site.lay
	var outside := site.to_global(Vector3(0.0, 1.6, 30.0))
	var at_window := site.to_global(Vector3(0.0, 1.6, 3.0))
	var inside := site.to_global(Vector3(0.0, 1.0, -D * 0.5))
	var at_door := site.to_global(Vector3(float(lay.door_x), 0.5, 1.2))
	site.evaluate([outside], outside)
	_check(not site.shown, "from across the street the glass draws the traced room")
	site.evaluate([at_window], outside)
	var clear := glass.material_override as ShaderMaterial
	_check(site.shown and interior.visible and clear != null and clear.shader.resource_path.ends_with("corner_store_clear.gdshader"),
			"at the window the real interior shows behind clear glass")
	site.evaluate([outside, at_door], at_door)
	await _ticks(45)
	var door := site.get_node("Door") as Node3D
	_check(site.door_open > 0.9 and absf(door.rotation.y) > deg_to_rad(80.0),
			"the door swings open for the player (%.2f, %.0f degrees)" % [site.door_open, rad_to_deg(door.rotation.y)])
	site.evaluate([inside], inside)
	await _ticks(45)
	_check(site.shown and site.door_open < 0.1, "inside, the interior stays shown and the door swings shut (%.2f)" % site.door_open)
	site.evaluate([outside], outside)
	_check(not site.shown and not interior.visible and glass.material_override == traced, "walking away hides the interior again")
	# Somebody at the till.
	var people := 0
	for p: Variant in site.people:
		if is_instance_valid(p):
			people += 1
	var us: Array = CornerStoreKit.last_step_us
	print("walk-in store: %s %.1f x %.1f, %d goods, %d people, chunk %.0f ms; store steps (ms) %s" % [s.name, W, D, goods, people, build_ms,
			us.map(func(x: int) -> String: return "%.1f" % (float(x) / 1000.0))])
	chunk.queue_free()
	await _ticks(2)


func _lod(s: Dictionary) -> void:
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = (s.block as Vector2i).x
	lod.iz = (s.block as Vector2i).y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": [], "custom": []})
	var panels := 0
	var near := 0
	var o: Vector2 = s.origin
	var xforms: Array = boxes.get("xforms", [])
	var customs: Array = boxes.get("custom", [])
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		if Vector2(xf.origin.x, xf.origin.z).distance_to(o) < 9.0:
			near += 1
			if i < customs.size() and customs[i] is Color and is_equal_approx((customs[i] as Color).a, FarBuilding.PLANT_FLAG):
				panels += 1
	_check(near >= 3 and panels >= 2, "the far city sees the store as a box with its lit sign (%d boxes, %d panels)" % [near, panels])
	lod.free()


## With the store off, every other building of the block stands where it stood (no roll moved).
func _unmoved(s: Dictionary) -> void:
	var positions := []
	for on: bool in [true, false]:
		CornerStore.enabled = on
		CornerStore._cache.clear()
		var lod := CityChunk.new()
		lod.plan = _plan
		lod.ix = (s.block as Vector2i).x
		lod.iz = (s.block as Vector2i).y
		lod.level = CityChunk.Level.LOD
		lod.style = _city.chunk_style()
		lod.capturing = true
		lod.build()
		var set := {}
		var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": []})
		var fp: Rect2 = (s.cell as Rect2).grow(1.0)
		for xf: Transform3D in boxes.get("xforms", []):
			if not fp.has_point(Vector2(xf.origin.x, xf.origin.z)):
				set["%.2f,%.2f,%.2f" % [xf.origin.x, xf.origin.y, xf.origin.z]] = true
		positions.append(set)
		lod.free()
	CornerStore.enabled = true
	CornerStore._cache.clear()
	var a: Dictionary = positions[0]
	var b: Dictionary = positions[1]
	var diff := 0
	for k: String in a:
		if not b.has(k):
			diff += 1
	for k: String in b:
		if not a.has(k):
			diff += 1
	_check(diff == 0 and a.size() > 0, "the rest of the block is the same with the store on and off (%d far boxes, %d differ)" % [a.size(), diff])
