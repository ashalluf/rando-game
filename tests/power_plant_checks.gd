extends RefCounted
## The power plant (PowerPlant, PowerPlantKit, PowerPlantBuild), for tests/smoke_test.gd. Loaded at
## run time, not named there, so it compiles after the autoloads.
##
## The site: on the coast south of the airport and the 105, snapped to whole blocks, streets inside
## closed and the four round it open, no city lots or other grounds on it, clear of the freeway and
## the mall. The layout, pure and repeatable: every piece inside the fence, no two of the big ones
## overlapping, the twin stacks the tallest things and lit. The line: towers in the ridges' form on
## ordinary blocks, clear of the freeway, spans within limits, conductors clear of the ground, its
## right of way taking lots and no house standing in it. The chunks: FULL lays one casting plant
## mesh on the plant shader under a triangle budget, its ground and collision; LOD the plant mesh
## at low detail; the far city records ground and boxes; the beach chunk builds the seawall; the
## landmark's wires and stack lights exist near and far.

var _t: Node

const MESH_BUDGET := 120000


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not PowerPlant.enabled:
		return  # POWER_PLANT=0, the A/B: there is no plant to check.
	var plan: CityPlan = city.plan
	var lay := PowerPlant.layout(plan)
	_t._check(not lay.is_empty() and bool(lay.ok), "the power plant has a site on the plan and is laid out")
	if lay.is_empty() or not bool(lay.ok):
		return
	_site(plan, lay)
	_layout(plan, lay)
	_line(plan, lay)
	_chunks(city, plan, lay)
	_landmark(plan)


func _site(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var R: Rect2 = lay.rect
	var m := plan.macro
	_t._check(R.position.y > m.airport_rect.end.y and R.position.x - m.coast_x(R.get_center().y) < 150.0,
		"the plant stands on the coast south of the airport (%s)" % R)
	var closed := true
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_X, ix, R.get_center().y)
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_Z, iz, R.get_center().x)
	var perimeter := plan.road_open(CityPlan.AXIS_X, int(s.ix0), R.get_center().y) and plan.road_open(CityPlan.AXIS_X, int(s.ix1), R.get_center().y) \
		and plan.road_open(CityPlan.AXIS_Z, int(s.iz0), R.get_center().x) and plan.road_open(CityPlan.AXIS_Z, int(s.iz1), R.get_center().x)
	_t._check(closed and perimeter, "every street inside the plant is closed (%s) and the four round it open (%s)" % [closed, perimeter])
	var lots := 0
	var site := true
	var grounds := 0
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			lots += plan.lots(ix, iz).size()
			var b := plan.block(ix, iz)
			site = site and String(b.get("site", "")) == PowerPlant.SITE_ID
			if b.has("grounds") or b.has("hospital"):
				grounds += 1
	_t._check(lots == 0 and site and grounds == 0, "the plant's blocks are its site: no city lots (%d), no other grounds (%d)" % [lots, grounds])
	_t._check(not m.freeway.blocks_rect((lay.fence as Rect2), 2.0), "no freeway deck or ramp crosses the plant's fence")
	var mall := Rect2()
	for lm in Landmarks.all():
		if lm.id == "south_bay_mall":
			var a: Vector2 = lm.anchor
			mall = Rect2(a.x - LandmarkSouthBayMall.SITE_HALF_X, a.y - LandmarkSouthBayMall.SITE_BACK,
				LandmarkSouthBayMall.SITE_HALF_X * 2.0, LandmarkSouthBayMall.SITE_BACK + LandmarkSouthBayMall.SITE_FRONT)
	_t._check(not mall.has_area() or not mall.intersects(lay.rect), "the plant keeps off the mall's ring road")


func _layout(plan: CityPlan, lay: Dictionary) -> void:
	var fence: Rect2 = lay.fence
	var inside := true
	var outside := []
	for p: Dictionary in lay.pieces:
		var sz: Vector3 = p.size
		var foot := Rect2((p.c as Vector2) - Vector2(sz.x, sz.z) * 0.5, Vector2(sz.x, sz.z))
		if not fence.grow(0.5).encloses(foot):
			inside = false
			outside.append(p.kind)
	_t._check(inside, "every piece stands inside the fence (%s)" % [outside])
	# The big pieces never overlap one another.
	var big := ["turbine_hall", "boiler_house", "stack", "filter_house", "gas_turbine", "hrsg", "hrsg_stack", "st_hall", "pump_house", "tank", "admin", "switchyard"]
	var hits := []
	var ps: Array = lay.pieces
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			var a: Dictionary = ps[i]
			var b: Dictionary = ps[j]
			if not (String(a.kind) in big and String(b.kind) in big):
				continue
			var sa: Vector3 = a.size
			var sb: Vector3 = b.size
			var ra := Rect2((a.c as Vector2) - Vector2(sa.x, sa.z) * 0.5, Vector2(sa.x, sa.z)).grow(-0.3)
			var rb := Rect2((b.c as Vector2) - Vector2(sb.x, sb.z) * 0.5, Vector2(sb.x, sb.z)).grow(-0.3)
			if ra.intersects(rb):
				hits.append("%s/%s" % [a.kind, b.kind])
	_t._check(hits.is_empty(), "the plant's buildings, stacks, tanks and yard keep apart (%s)" % [hits])
	var tall := 0
	var top := 0.0
	for p: Dictionary in lay.pieces:
		if String(p.kind) == "stack":
			tall += 1
		elif String(p.kind) != "stack":
			top = maxf(top, (p.size as Vector3).y)
	_t._check(tall == 2 and PowerPlant.STACK_H > top + 20.0, "the twin stacks are the plant's tallest things (%.0f m over %.0f m)" % [PowerPlant.STACK_H, top])
	PowerPlant._layouts.clear()
	var again := PowerPlant.layout(plan)
	_t._check((again.pieces as Array).size() == (lay.pieces as Array).size() and (again.pieces[0].c as Vector2).is_equal_approx(lay.pieces[0].c),
		"the plant's layout is pure: built twice, the same")


func _line(plan: CityPlan, lay: Dictionary) -> void:
	var ln := PowerPlant.line(plan)
	_t._check(not ln.is_empty() and (ln.towers as Array).size() >= 3, "a line leaves the switchyard on lattice towers (%d)" % (0 if ln.is_empty() else (ln.towers as Array).size()))
	if ln.is_empty():
		return
	var fw: Freeway = plan.macro.freeway
	var ok := true
	var spans := true
	var prev: Vector2 = lay.gantry.pos
	for t: Dictionary in ln.towers:
		var p: Vector2 = t.pos
		var foot := Rect2(p - Vector2(5.0, 5.0), Vector2(10.0, 10.0))
		if fw.blocks_rect(foot, 2.0) or plan.zone_at(p) != MacroMap.Zone.CITY:
			ok = false
		var k := plan.block_index_at(p)
		var b := plan.block(k.x, k.y)
		if not ((b.rect as Rect2).grow(-plan.sidewalk_width).encloses(foot)) or b.has("site"):
			ok = false
		var d := p.distance_to(prev)
		if d > PowerPlant.MAX_SPAN + 45.0 or d < 40.0:
			spans = false
		prev = p
	_t._check(ok, "every tower stands inside an ordinary block, off the freeway and its ramps")
	_t._check(spans, "every span is within the line's limits")
	# Conductors stay clear of the ground mid-span (the ridges' sag).
	var low := INF
	var towers: Array = ln.towers
	for k in range(1, towers.size()):
		var a := Ridges.attach(towers[k - 1], towers[k].pos)
		var b := Ridges.attach(towers[k], towers[k - 1].pos)
		var mid := Ridges.wire(a[0], b[0], 8)[4]
		low = minf(low, mid.y - plan.macro.relief_at(Vector2(mid.x, mid.z)))
	_t._check(low > 8.0, "the lowest conductor mid-span is %.1f m over the ground" % low)
	# The right of way takes lots, and no house is put back in it.
	var houses := 0
	var taken := 0
	for t: Dictionary in towers:
		var k := plan.block_index_at(t.pos)
		for lot: Dictionary in plan.lots(k.x, k.y):
			if PowerPlant.claims_lot(plan, k.x, k.y, Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)):
				taken += 1
		for lot: Dictionary in HouseKit.extra_lots(plan, k.x, k.y):
			if PowerPlant.claims_cell(plan, lot.cell):
				houses += 1
	_t._check(taken == 0 and houses == 0, "no lot or house stands in the right of way (%d lots, %d houses)" % [taken, houses])


func _chunks(city: Node3D, plan: CityPlan, lay: Dictionary) -> void:
	# The chunk holding the stacks: FULL.
	var k := plan.chunk_index_at(PowerPlant.ANCHOR)
	for p: Dictionary in lay.pieces:
		if String(p.kind) == "stack":
			k = plan.chunk_index_at(p.c)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var mesh: MeshInstance3D = chunk.get_node_or_null("PowerPlant")
	var shader_ok := mesh != null and mesh.mesh.get_surface_count() == 1 and (mesh.mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path.ends_with("power_plant.gdshader")
	_t._check(shader_ok and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "a FULL plant chunk lays one casting mesh on the plant shader")
	var tris := CityChunk._mesh_tris(mesh.mesh) if mesh else 0
	_t._check(tris > 5000 and tris < MESH_BUDGET, "its plant mesh is %d triangles (budget %d)" % [tris, MESH_BUDGET])
	var ground: MeshInstance3D = chunk.get_node_or_null("PowerPlantGround")
	_t._check(ground != null and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "its ground is one shadowless mesh")
	var shapes := 0
	var buildings := 0
	for c in chunk.get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
		if c is Building:
			buildings += 1
	_t._check(shapes >= 10 and buildings == 0, "its halls, stacks and ground collide (%d shapes) and no city Building stands there (%d)" % [shapes, buildings])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var lm: MeshInstance3D = lod.get_node_or_null("PowerPlant")
	var lod_tris := CityChunk._mesh_tris(lm.mesh) if lm else 0
	_t._check(lm != null and lod_tris < tris * 0.6, "a LOD plant chunk draws the plant at low detail (%d triangles, FULL %d)" % [lod_tris, tris])
	lod.get_parent().remove_child(lod)
	lod.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var slabs := (cap.captured.get("ground", []) as Array).size()
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	_t._check(slabs >= 1 and (boxes.get("xforms", []) as Array).size() >= 3,
		"the far city records the plant's ground (%d slabs) and its masses (%d far boxes)" % [slabs, (boxes.get("xforms", []) as Array).size()])
	cap.free()
	# The beach chunk in front builds the seawall.
	var R: Rect2 = lay.rect
	var m := plan.macro
	var zc := R.get_center().y
	var bk := plan.chunk_index_at(Vector2(m.coast_x(zc) + m.beach_width_at(zc) - 2.0, zc))
	var beach: CityChunk = city._new_chunk(bk, CityChunk.Level.FULL)
	beach.build()
	var wall: MeshInstance3D = beach.get_node_or_null("PowerPlant")
	_t._check(wall != null and CityChunk._mesh_tris(wall.mesh) > 200, "the beach in front of the plant has its seawall (%d triangles)" % (CityChunk._mesh_tris(wall.mesh) if wall else 0))
	beach.get_parent().remove_child(beach)
	beach.free()


func _landmark(plan: CityPlan) -> void:
	var holder := Node3D.new()
	var lm: Dictionary = {}
	for e in Landmarks.all():
		if e.id == PowerPlant.SITE_ID:
			lm = e
	_t._check(not lm.is_empty(), "the plant is a landmark (its wires and lights are drawn near and far)")
	if lm.is_empty():
		holder.free()
		return
	Landmarks.build(lm, holder, null, plan, false)
	var wires := holder.get_node_or_null("PlantWires") as MeshInstance3D
	var lights := holder.get_node_or_null("StackLights") as MeshInstance3D
	_t._check(wires != null and wires.mesh.get_surface_count() >= 1 and (wires.mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path.ends_with("power_wire.gdshader"),
		"the line's conductors are drawn on the ridges' wire shader")
	var n := 0
	if lights:
		n = (lights.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 6
	_t._check(n >= 12, "the stacks carry their aviation lights (%d)" % n)
	holder.free()
