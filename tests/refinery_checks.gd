extends RefCounted
## The oil refinery (Refinery, RefineryKit, RefineryFar), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## The site: INDUSTRIAL, north of the port, snapped to whole blocks, every street inside closed and
## the perimeter open, no city lots on its blocks. The layout, pure and repeatable: the tank farm,
## process units, flares, cooling towers and the gate, every item inside the fence, the tanks inside
## their berms and apart, the flares away from the gate. The chunks: FULL lays the plant as one
## casting mesh on the refinery shader under a triangle budget, its lights, flames or steam, its
## collision and a cover; LOD lays the ground and no plant; the far city records the ground. The
## far pieces: one a block, lit, hidden under a shown FULL chunk. The shaders compile.

var _t: Node

## Triangles a FULL site chunk's plant mesh may hold.
const MESH_BUDGET := 260000


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not Refinery.enabled:
		return  # REFINERY=0, the A/B: there is no plant to check.
	var plan: CityPlan = city.plan
	var lay := Refinery.layout(plan)
	_t._check(not lay.is_empty(), "the refinery has a site on the plan")
	if lay.is_empty():
		return
	_site(plan, lay)
	_layout(plan, lay)
	var s: Dictionary = lay.site
	# The busiest chunk (most items) and a tank chunk.
	var best := Vector2i(int(s.ix0), int(s.iz0))
	var most := -1
	var tank := Vector2i(-99999, 0)
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			var n := 0
			for it: Dictionary in lay.items:
				if plan.owned_rect(ix, iz).has_point(it.at):
					n += 1
					if it.type == "ftank" and tank.x == -99999:
						tank = Vector2i(ix, iz)
			if n > most:
				most = n
				best = Vector2i(ix, iz)
	_full_chunk(city, plan, best)
	if tank.x != -99999:
		_full_chunk(city, plan, tank)
	_lod_chunk(city, plan, best)
	_capture(city, plan, best)
	_far(city, plan, lay)
	_shaders()


func _site(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var R: Rect2 = lay.rect
	_t._check(plan.district_at(R.get_center()) == CityPlan.District.INDUSTRIAL, "the refinery stands in the industrial district")
	var port: Rect2 = plan.macro.port_rect
	_t._check(R.end.y < port.position.y + 1.0 and R.end.y > port.position.y - 260.0 and R.position.x < port.end.x and R.end.x > port.position.x,
		"it stands just north of the port (rect %s, port %s)" % [R, port])
	_t._check(int(s.ix1) - int(s.ix0) >= 3 and int(s.iz1) - int(s.iz0) >= 4 and R.size.x > 300.0 and R.size.y > 400.0,
		"the plant takes %d x %d blocks (%.0f x %.0f m)" % [int(s.ix1) - int(s.ix0), int(s.iz1) - int(s.iz0), R.size.x, R.size.y])
	var closed := true
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_X, ix, R.get_center().y)
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_Z, iz, R.get_center().x)
	_t._check(closed, "every street inside the plant is closed")
	var open := plan.road_open(CityPlan.AXIS_X, int(s.ix0), R.get_center().y) and plan.road_open(CityPlan.AXIS_X, int(s.ix1), R.get_center().y) \
		and plan.road_open(CityPlan.AXIS_Z, int(s.iz0), R.get_center().x) and plan.road_open(CityPlan.AXIS_Z, int(s.iz1), R.get_center().x)
	_t._check(open, "the streets round it stay open")
	var lots := 0
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			lots += plan.lots(ix, iz).size()
	_t._check(lots == 0, "no city lots on the plant's blocks (%d)" % lots)
	_t._check(not plan.macro.freeway.blocks_rect(R.grow(-(Refinery.PAVEMENT + 6.0)), 0.0), "no freeway deck crosses the plant")


func _layout(plan: CityPlan, lay: Dictionary) -> void:
	var again := Refinery._make_layout(plan)
	_t._check(again.items.size() == lay.items.size() and again.racks.size() == lay.racks.size() and str(again.gate) == str(lay.gate),
		"the layout is pure (%d items, %d racks)" % [lay.items.size(), lay.racks.size()])
	var counts := {}
	for it: Dictionary in lay.items:
		counts[it.type] = int(counts.get(it.type, 0)) + 1
	_t._check(int(counts.get("ftank", 0)) >= 6, "a tank farm of floating-roof tanks (%d)" % int(counts.get("ftank", 0)))
	_t._check(int(counts.get("flare", 0)) >= 1 and int(counts.get("cooling", 0)) >= 1 and int(counts.get("sphere", 0)) >= 2,
		"flares (%d), cooling towers (%d) and pressure spheres (%d)" % [int(counts.get("flare", 0)), int(counts.get("cooling", 0)), int(counts.get("sphere", 0))])
	_t._check(int(counts.get("column", 0)) >= 6 and int(counts.get("structure", 0)) >= 3 and int(counts.get("heater", 0)) >= 3,
		"process units: columns (%d), structures (%d), heaters (%d)" % [int(counts.get("column", 0)), int(counts.get("structure", 0)), int(counts.get("heater", 0))])
	var variants := {}
	for sb: Dictionary in lay.subs:
		if sb.role == "process":
			variants[sb.variant] = true
	_t._check(variants.size() >= 3, "at least three kinds of process unit (%d)" % variants.size())
	_t._check(lay.racks.size() >= 20, "pipe racks down the plant's streets (%d pieces)" % lay.racks.size())
	var inner: Rect2 = lay.inner
	var outside := 0
	for it: Dictionary in lay.items:
		if not inner.grow(1.0).has_point(it.at):
			outside += 1
	_t._check(outside == 0, "every item stands inside the fence (%d outside)" % outside)
	# Tanks inside their berms, and none overlapping another.
	var tanks: Array = lay.items.filter(func(it: Dictionary) -> bool: return it.type == "ftank" or it.type == "ctank")
	var in_berm := 0
	for tk: Dictionary in tanks:
		for b: Rect2 in lay.berms:
			if b.has_point(tk.at) and b.grow(-float(tk.D) * 0.5 + 0.5).has_point(tk.at):
				in_berm += 1
				break
	_t._check(in_berm == tanks.size(), "every tank sits inside its berm (%d of %d)" % [in_berm, tanks.size()])
	var overlaps := 0
	for i in tanks.size():
		for j in range(i + 1, tanks.size()):
			if (tanks[i].at as Vector2).distance_to(tanks[j].at) < (float(tanks[i].D) + float(tanks[j].D)) * 0.5 + 3.0:
				overlaps += 1
	_t._check(overlaps == 0, "no two tanks overlap (%d)" % overlaps)
	var g: Vector2 = lay.gate.at
	var near := 9999.0
	for it: Dictionary in lay.items:
		if it.type == "flare":
			near = minf(near, g.distance_to(it.at))
	_t._check(near > 300.0, "the flares stand far from the gate (%.0f m)" % near)


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var plant: MeshInstance3D = chunk.get_node_or_null("RefineryPlant")
	var ground: MeshInstance3D = chunk.get_node_or_null("RefineryGround")
	var shader_ok := plant != null and plant.material_override is ShaderMaterial and (plant.material_override as ShaderMaterial).shader.resource_path.ends_with("refinery.gdshader")
	_t._check(shader_ok and plant.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "a FULL refinery chunk %s lays its plant as one casting mesh on the refinery shader" % k)
	_t._check(ground != null and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "its yard ground is one shadowless mesh")
	var tris := CityChunk._mesh_tris(plant.mesh) if plant else 0
	_t._check(tris > 3000 and tris < MESH_BUDGET, "its plant mesh is %d triangles (budget %d)" % [tris, MESH_BUDGET])
	var lights: MeshInstance3D = chunk.get_node_or_null("RefineryLights")
	_t._check(lights != null and lights.mesh.surface_get_array_len(0) / 6 >= 10, "its lamps are one billboard mesh (%d lamps)" % (lights.mesh.surface_get_array_len(0) / 6 if lights else 0))
	var shapes := 0
	for c in chunk.get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
	_t._check(shapes >= 10, "its tanks, structures and ground collide (%d shapes)" % shapes)
	var cover := false
	var buildings := 0
	for c in chunk.get_children():
		if c is RefineryCover:
			cover = (c as RefineryCover).key == k
		if c is Building:
			buildings += 1
	_t._check(cover and buildings == 0, "it leaves a cover for its block and builds no city Building")
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var cover := false
	for c in chunk.get_children():
		cover = cover or c is RefineryCover
	_t._check(chunk.get_node_or_null("RefineryPlant") == null and not cover, "a LOD refinery chunk lays the ground and leaves the plant to the far piece")
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _capture(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var ground := (cap.captured.get("ground", []) as Array).size()
	_t._check(ground >= 1, "the far city records the plant's ground (%d slabs)" % ground)
	cap.free()


func _far(city: Node3D, plan: CityPlan, lay: Dictionary) -> void:
	var far: RefineryFar = city.get_node_or_null("RefineryFar")
	_t._check(far != null, "the streamer holds the refinery's far pieces")
	if far == null:
		return
	var s: Dictionary = lay.site
	var blocks := (int(s.ix1) - int(s.ix0)) * (int(s.iz1) - int(s.iz0))
	_t._check(far.piece_count() >= blocks - 2, "a far piece a block (%d for %d blocks)" % [far.piece_count(), blocks])
	var lit := 0
	var flames := 0
	for piece in far.get_children():
		if piece.get_node_or_null("Lights"):
			lit += 1
		if piece.get_node_or_null("RefineryFlames"):
			flames += 1
	_t._check(lit >= blocks - 2 and flames >= 1, "the far pieces carry their lamps (%d) and the flares' flames (%d)" % [lit, flames])
	# A shown chunk's cover hides its block's far piece; gone, the piece shows again.
	var k := Vector2i(int(s.ix0), int(s.iz0))
	var holder := Node3D.new()
	city.add_child(holder)
	var cover := RefineryCover.new()
	cover.key = k
	holder.add_child(cover)
	far._tick = 0.0
	far._process(0.0)
	var hidden := not (far._pieces[k] as Node3D).visible if far._pieces.has(k) else false
	holder.queue_free()
	city.remove_child(holder)
	far._tick = 0.0
	far._process(0.0)
	var shown := (far._pieces[k] as Node3D).visible if far._pieces.has(k) else false
	_t._check(hidden and shown, "a shown FULL chunk hides its block's far piece, and it comes back")


func _shaders() -> void:
	for path: String in ["res://shaders/refinery.gdshader", "res://shaders/refinery_flame.gdshader", "res://shaders/refinery_plume.gdshader"]:
		var sh := load(path) as Shader
		_t._check(sh != null and sh.get_code().length() > 100, "%s loads" % path.get_file())
	# The shader's kinds are the kit's (the last one, soot, is 19).
	var code := (load("res://shaders/refinery.gdshader") as Shader).get_code()
	_t._check(code.contains("19 soot") and RefineryKit.K_SOOT == 19 and RefineryKit.K_RAIL == 6 and code.contains("6 handrail"), "the shader's kind table matches the kit's")
