extends RefCounted
## Places of worship (Worship, WorshipBuild) for tests/smoke_test.gd. Loaded at run time (not
## named there), so it compiles after the autoloads.
## Checks: the sites are pure (the same answer twice) and every kind stands somewhere in the
## basin; a site is whole lots of its own block, inside its pavement ring, clear of the freeway
## and of the stations' blocks, and no extra house is put in it; its chunk builds the building
## with a sanctuary body, its Sanctuary zone and its night lights, and the guns refuse to fire into
## it; the far city sees it; street wear and encampments keep their distance.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_ws = _tree.root.get_node("/root/WorldState")
	var all := _pure()
	if all.is_empty():
		return
	# One chunk of each kind (the nearest of each to the spawn).
	var by_kind := {}
	for s: Dictionary in all:
		var k := int(s.kind)
		var d := (s.site as Rect2).get_center().length()
		if not by_kind.has(k) or d < (by_kind[k].site as Rect2).get_center().length():
			by_kind[k] = s
	for k: int in by_kind:
		await _chunk(by_kind[k])


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _pure() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	var kinds := {}
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var s := Worship.for_cell(_plan, Vector2i(cx, cz))
			if not s.is_empty():
				all.append(s)
				kinds[int(s.kind)] = int(kinds.get(int(s.kind), 0)) + 1
	_check(all.size() >= 12, "places of worship stand across the city (%d)" % all.size())
	_check(kinds.size() == Worship.Kind.size(), "every kind stands somewhere: mission, modern, storefront, greek, temple, synagogue (%s)" % str(kinds))
	if all.is_empty():
		return all
	var found: Dictionary = all[0]
	Worship._cache.clear()
	var again := Worship.for_cell(_plan, found.cell)
	_check(not again.is_empty() and again.block == found.block and int(again.builder) == int(found.builder) and again.name == found.name
			and int(again.kind) == int(found.kind), "a place of worship is worked out the same way twice (%s)" % found.name)
	var bad: Array[String] = []
	for s: Dictionary in all:
		var bx: int = s.block.x
		var bz: int = s.block.y
		var b := _plan.block(bx, bz)
		var inner := (b.rect as Rect2).grow(-_plan.sidewalk_width + 0.01)
		var site: Rect2 = s.site
		var claimed := 0
		var builders := 0
		for lot: Dictionary in _plan.lots(bx, bz):
			if Worship.claims(_plan, bx, bz, lot):
				claimed += 1
				if not site.has_point(lot.center):
					bad.append("%s lot outside" % s.name)
				if int(lot.seed) == int(s.builder):
					builders += 1
			elif site.grow(-0.5).has_point(lot.center):
				bad.append("%s unclaimed lot inside" % s.name)
		for lot: Dictionary in HouseKit.extra_lots(_plan, bx, bz):
			if site.grow(-0.5).has_point(lot.center):
				bad.append("%s extra house inside" % s.name)
		var fs := FireStation.for_cell(_plan, FireStation._cell_of((b.rect as Rect2).get_center()))
		if claimed != (s.lots as Array).size() or claimed == 0 or builders != 1 or not inner.encloses(site):
			bad.append("%s lots %d/%d" % [s.name, claimed, (s.lots as Array).size()])
		if (not fs.is_empty() and fs.block == s.block) or not PoliceStation.station_on(_plan, bx, bz).is_empty():
			bad.append("%s on a station's block" % s.name)
		if _plan.macro.freeway and _plan.macro.freeway.blocks_rect(site, 3.0):
			bad.append("%s under the freeway" % s.name)
		if b.has("site") or b.has("grounds") or Landmarks.claims(b.rect):
			bad.append("%s on a claimed block" % s.name)
		if Encampment._block_ok(_plan, bx, bz):
			bad.append("%s allows a camp on its block" % s.name)
	_check(bad.is_empty(), "every site is whole lots of its own block, unclaimed by anything else, clear of the freeway, no extra house or camp in it (%s)" % str(bad.slice(0, 4)))
	return all


func _chunk(s: Dictionary) -> void:
	var kname: String = Worship.KIND_NAMES[int(s.kind)]
	var chunk: CityChunk = _city._new_chunk(s.block, CityChunk.Level.FULL)
	chunk.build()
	var node: Node3D = null
	for n in chunk.get_children():
		if n.is_in_group("worship"):
			node = n
	var zone: Node3D = null
	for n in chunk.get_children():
		if n.name == "WorshipZone":
			zone = n
	_check(node != null and node.has_node("Building") and node.has_node("Body") and node.get_node("Body").is_in_group(Sanctuary.BODY_GROUP),
			"%s: its chunk builds the building with a sanctuary body (%s)" % [kname, s.name])
	if node == null:
		chunk.queue_free()
		await _ticks(2)
		return
	var tris := 0
	var m := (node.get_node("Building") as MeshInstance3D).mesh
	for si in m.get_surface_count():
		tris += m.surface_get_array_len(si) / 3
	var budget := 30000 if int(s.kind) == Worship.Kind.STOREFRONT else 120000
	_check(tris > 400 and tris < budget, "%s: real geometry inside its budget (%d triangles, %d surfaces)" % [kname, tris, m.get_surface_count()])
	var lamps := 0
	for n in node.get_children():
		if n is OmniLight3D and n.is_in_group("lamp_light"):
			lamps += 1
	_check(lamps >= 1, "%s: lit at night (%d lamps)" % [kname, lamps])
	# The zone: over the site, and the guns refuse to shoot into it.
	var site: Rect2 = s.site
	var c := site.get_center()
	var h := _plan.height_at(c)
	var inside: Vector3 = _ws.to_local(Vector3(c.x, h + 3.0, c.y))
	_check(zone != null and Sanctuary.contains(_tree, inside), "%s: a Sanctuary zone covers the grounds" % kname)
	var shooter := Node3D.new()
	_city.add_child(shooter)
	var out := c - (s.frame.n as Vector2) * 60.0
	shooter.global_position = _ws.to_local(Vector3(out.x, _plan.height_at(out) + 1.6, out.y))
	var aim := {"origin": shooter.global_position, "point": inside, "collider": null}
	var away := shooter.global_position + Vector3((s.frame.a as Vector2).x, 0.0, (s.frame.a as Vector2).y) * 30.0 + Vector3.UP * 2.0
	var aim_away := {"origin": shooter.global_position, "point": away, "collider": null}
	_check(Sanctuary.blocks_fire(shooter, aim) and Sanctuary.blocks_fire(shooter, {"origin": shooter.global_position, "point": away, "collider": node.get_node("Body")}),
			"%s: a shot across its grounds or at the building is refused" % kname)
	_check(not Sanctuary.blocks_fire(shooter, aim_away), "%s: a shot down the street beside it is not" % kname)
	shooter.queue_free()
	# Street wear keeps off it.
	var pts: PackedVector2Array = chunk.get_meta("street_wear", PackedVector2Array())
	var near := 0
	for p in pts:
		if site.grow(StreetWear.WORSHIP_MARGIN * 0.5).has_point(p):
			near += 1
	_check(near == 0, "%s: no tag, poster or grime on or round it (%d of %d)" % [kname, near, pts.size()])
	# The far city sees it.
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = s.block.x
	lod.iz = s.block.y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": []})
	var in_site := 0
	for xf: Transform3D in boxes.xforms:
		if site.grow(1.0).has_point(Vector2(xf.origin.x, xf.origin.z)) and xf.basis.get_scale().y > 3.0:
			in_site += 1
	_check(in_site > 0, "%s: the far city sees it (%d boxes)" % [kname, in_site])
	chunk.queue_free()
	lod.free()
	await _ticks(2)
