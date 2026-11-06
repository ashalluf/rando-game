extends RefCounted
## The hillside houses on the estates (HillHomeKit, HillHomeBuild), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Every estate HillRoads places gets a plan: pure (the same estate plans the same house twice),
## all three types there, its view on a side that is not the road's, every wing on the pad but for
## a cantilever's overhang and the lower levels stepping down the view side, no two wings at the
## same level overlapping, the garage clear of the gate's corridor, the pool on the pad, heights a
## house's. Then the FULL chunk round a steep estate: the houses one mesh per material, the glass on
## the hillside glass shader, one collision body, no Building slab, a triangle budget per house, the
## build time; the LOD chunk: boxes in the lod_box batch; the far city's boxes, a glowing glass band
## among them; and with the kit off the old slab is back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	if plan.macro == null or plan.macro.hill_roads == null:
		_t._check(false, "hill homes: the plan has hill roads")
		return
	var estates: Array = plan.macro.hill_roads.mansions
	_t._check(estates.size() > 50, "hill homes: there are estates to build on (%d)" % estates.size())
	_plans(plan, estates)
	var steep := _steep(plan, estates)
	if steep.is_empty():
		_t._check(false, "hill homes: there is a steep estate with a cantilever")
		return
	_full(city, plan, steep)
	_lod(city, plan, steep)
	_far(plan, steep)
	_off(city, plan, steep)


func _plans(plan: CityPlan, estates: Array) -> void:
	var styles := {}
	var impure := 0
	var astray := 0
	var overlaps := 0
	var road_view := 0
	var garage_in_gate := 0
	var pool_off := 0
	var tall := 0
	var t0 := Time.get_ticks_usec()
	for m: Dictionary in estates:
		var h := HillHomeKit.plan_home(plan, m)
		styles[h.style_name] = int(styles.get(h.style_name, 0)) + 1
		var Wp: float = h.Wp
		var Dp: float = h.Dp
		var over: float = h.cantilever
		if h.view_side == "road":
			road_view += 1
		var wings: Array = h.wings
		for i in wings.size():
			var w: Dictionary = wings[i]
			var r: Rect2 = w.r
			var y: float = w.y
			var reach := Dp + over + 0.2
			if y < -0.5:
				reach = Dp + 12.0
			if r.position.x < -0.05 or r.end.x > Wp + 0.05 or r.position.y < -0.05 or r.end.y > reach:
				astray += 1
			for j in range(i + 1, wings.size()):
				var q: Dictionary = wings[j]
				var y0 := maxf(y, float(q.y))
				var y1 := minf(y + float(w.storeys) * HouseKit.STOREY, float(q.y) + float(q.storeys) * HouseKit.STOREY)
				if y1 - y0 > 0.5 and r.grow(-0.1).intersects((q.r as Rect2).grow(-0.1)):
					# A villa's tower stands against the main wing's front; nothing else touches.
					if not (w.role == "main" and q.role == "tower"):
						overlaps += 1
		var gd: Dictionary = h.garage
		if not gd.is_empty():
			var gr: Rect2 = (wings[int(gd.wing)].r as Rect2)
			var gate: Vector2 = h.gate
			var corridor := Rect2(gate - Vector2(2.6, 2.6), Vector2(5.2, 5.2))
			if gr.intersects(corridor):
				garage_in_gate += 1
		var pl: Dictionary = h.pool
		if not pl.is_empty():
			var pr: Rect2 = pl.r
			if pr.position.x < 0.0 or pr.end.x > Wp or pr.position.y < 0.0 or pr.end.y > Dp + 0.01:
				pool_off += 1
		if float(h.height) > 16.0 or float(h.height) < 3.0:
			tall += 1
		if hash(var_to_str(HillHomeKit.plan_home(plan, m))) != hash(var_to_str(h)):
			impure += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_t._check(styles.size() == 3, "hill homes: all three types are planned (%s)" % str(styles))
	_t._check(impure == 0, "hill homes: the plans are pure (%d differ when planned twice)" % impure)
	_t._check(astray == 0 and overlaps == 0, "hill homes: every wing on its pad or over its view side (%d astray), none overlapping another at its level (%d)" % [astray, overlaps])
	_t._check(road_view == 0 and garage_in_gate == 0 and pool_off == 0, "hill homes: no view over the road (%d), garages clear of the gate (%d), pools on the pad (%d)" % [road_view, garage_in_gate, pool_off])
	_t._check(tall == 0, "hill homes: every house between 3 and 16 m tall (%d not)" % tall)
	print("HILL_HOMES plans %d estates (twice) in %.0f ms: %s" % [estates.size(), ms, str(styles)])


## A steep estate with a cantilever (columns down the slope), else the steepest one.
func _steep(plan: CityPlan, estates: Array) -> Dictionary:
	var best := {}
	var best_drop := -1.0
	for m: Dictionary in estates:
		var h := HillHomeKit.plan_home(plan, m)
		var d: float = h.drop + (100.0 if int(h.style) == HillHomeKit.Style.CANTILEVER else 0.0)
		if d > best_drop:
			best_drop = d
			best = m
	return best


func _chunk_for(city: Node3D, plan: CityPlan, m: Dictionary, level: int) -> CityChunk:
	var k: Vector2i = plan.block_index_at(m.pos)
	var chunk: CityChunk = city._new_chunk(k, level)
	return chunk


func _full(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var chunk := _chunk_for(city, plan, m, CityChunk.Level.FULL)
	var t0 := Time.get_ticks_usec()
	chunk.build()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var meshes := {}
	var tris := 0
	var bodies := 0
	var buildings := 0
	var glass_ok := false
	for c in chunk.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("HillHome_"):
			var name := str(c.name).trim_prefix("HillHome_")
			meshes[name] = true
			var mesh: Mesh = (c as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				tris += mesh.surface_get_array_len(si) / 3
			if name == "hh_glass":
				var mat := (c as MeshInstance3D).material_override as ShaderMaterial
				glass_ok = mat != null and mat.shader != null and mat.shader.resource_path.ends_with("hill_glass.gdshader")
		elif c is StaticBody3D and str(c.name) == "HillHomes":
			bodies += 1
		elif c is Building:
			buildings += 1
	var n := plan.macro.hill_roads.mansions_in(chunk.owned_rect()).size()
	_t._check(n > 0 and meshes.has("h_wall") and meshes.has("hh_glass") and meshes.has("h_trim") and meshes.size() <= HillHomeKit.MATS.size(),
		"hill homes: the FULL chunk's %d houses are one mesh per material (%s)" % [n, meshes.keys()])
	_t._check(glass_ok, "hill homes: the glass walls wear hill_glass.gdshader")
	_t._check(bodies == 1 and buildings == 0 and not chunk.has_meta("hill_home_kit"), "hill homes: one collision body, no Building slab (%d), the lists spent" % buildings)
	_t._check(tris > n * 1500 and tris < n * 40000, "hill homes: %d triangles for %d houses (1.5k-40k a house)" % [tris, n])
	print("HILL_HOMES full chunk %s: %d houses, %d triangles, build %.0f ms" % [plan.block_index_at(m.pos), n, tris, ms])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var chunk := _chunk_for(city, plan, m, CityChunk.Level.LOD)
	chunk.build()
	var boxes := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and str(c.name).contains("lod_box"):
			boxes += (c as MultiMeshInstance3D).multimesh.instance_count
	var n := plan.macro.hill_roads.mansions_in(chunk.owned_rect()).size()
	_t._check(boxes >= n * 3, "hill homes: the LOD chunk draws its %d houses as LOD boxes (%d)" % [n, boxes])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _far(plan: CityPlan, m: Dictionary) -> void:
	var fb := HillHomeKit.far_boxes(plan, m)
	var glow := 0
	var bad := 0
	for b: Array in fb:
		if float(b[2]) > 0.5:
			glow += 1
		var xf: Transform3D = b[0]
		if not xf.origin.is_finite() or xf.basis.determinant() <= 0.0:
			bad += 1
	_t._check(fb.size() >= 3 and glow >= 1 and bad == 0, "hill homes: the far city's boxes (%d, %d glass bands that glow after dark, %d bad)" % [fb.size(), glow, bad])
	var canopy := load("res://shaders/far_canopy.gdshader") as Shader
	_t._check(canopy != null and canopy.code.contains("estate_light"), "hill homes: far_canopy.gdshader lights the estates' glass bands")


func _off(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	HillHomeKit.enabled = false
	var chunk := _chunk_for(city, plan, m, CityChunk.Level.FULL)
	chunk.build()
	var buildings := 0
	var homes := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
		elif str(c.name).begins_with("HillHome_"):
			homes += 1
	HillHomeKit.enabled = true
	_t._check(buildings > 0 and homes == 0, "hill homes: with the kit off the estates are Building slabs again (%d)" % buildings)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
