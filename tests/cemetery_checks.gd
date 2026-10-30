extends RefCounted
## Memorial parks (Cemetery, CemeteryBuild, CemeteryKit), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Placement over the basin: parks on suburban blocks, PARK with grounds "cemetery" and no lots,
## never a school's or a rec park's; pure (a fresh decision of every cell is the same); the inner
## streets closed, the outer ones open. The plan: drive, gate, buildings, trees and stones inside the
## site, no stone on the drive or a building, a gentle rise (zero at the wall). A FULL chunk: the
## lawn, the collision all in the sanctuary body, a sanctuary zone over the park that the guns'
## rule sees, nothing breakable; LOD keeps the zone; the far city's capture records the lawn and
## no zone. The kit's meshes and the shaders' kinds.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_kit()
	var parks := _placement(plan)
	_t._check(parks.size() >= 1, "memorial parks: the basin has at least one (%d)" % parks.size())
	if parks.is_empty():
		return
	_purity(plan, parks)
	for d: Dictionary in parks:
		_roads(plan, d)
		_plan(plan, d)
	await _chunks(city, plan, parks[0])


func _kit() -> void:
	var src: String = (load("res://shaders/cemetery_stone.gdshader") as Shader).code
	var ok := true
	for k in 8:
		if not src.contains("k == %d" % k):
			ok = false
	_t._check(ok, "the cemetery stone shader draws each surface kind")
	var sizes := []
	var good := true
	for key: String in CemeteryKit.MESHES:
		var m := CemeteryKit.mesh(key)
		var tris := 0
		if m != null and m.get_surface_count() == 1:
			tris = (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		sizes.append("%s %d" % [key, tris])
		if tris < 10 or tris > 3000:
			good = false
	_t._check(good, "the cemetery kit builds every stone as one mesh of 10-3000 triangles (%s)" % [", ".join(sizes)])


## Every park over the basin, decided cell by cell.
func _placement(plan: CityPlan) -> Array:
	var out: Array = []
	var bad: Array = []
	var box := Rect2(-6000.0, -6000.0, 12000.0, 12000.0)
	var c0 := Cemetery._cell_of(box.position)
	var c1 := Cemetery._cell_of(box.end)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var d := Cemetery.decide(plan, Vector2i(cx, cz))
			if d.is_empty():
				continue
			out.append(d)
			for k: Vector2i in d.blocks:
				var b := plan.block(k.x, k.y)
				if int(b.district) != CityPlan.District.SUBURBS or int(b.kind) != CityPlan.BlockKind.PARK \
						or String(b.get("grounds", "")) != "cemetery" or not plan.lots(k.x, k.y).is_empty() or b.has("school"):
					bad.append(k)
	_t._check(bad.is_empty(), "memorial parks: every block is a suburban PARK with grounds 'cemetery' and no lots (bad %s)" % [bad])
	return out


## A second decision of every park's cell from cleared caches is the same.
func _purity(plan: CityPlan, parks: Array) -> void:
	var cells := {}
	for d: Dictionary in parks:
		cells[d.cell] = (d.blocks as Array).duplicate()
	var saved: Dictionary = Cemetery._cells
	Cemetery._cells = {}
	var same := true
	for c: Vector2i in cells:
		var d := Cemetery.decide(plan, c)
		if d.is_empty() or str(d.blocks) != str(cells[c]):
			same = false
	Cemetery._cells = saved
	_t._check(same, "memorial parks: deciding the cells again gives the same blocks")


func _roads(plan: CityPlan, d: Dictionary) -> void:
	var site: Rect2 = d.site
	var ok := true
	for cl: Array in d.closed:
		var axis: int = cl[0]
		var idx: int = cl[1]
		var mid := (float(cl[2]) + float(cl[3])) * 0.5
		if plan.road_open(axis, idx, mid):
			ok = false
	# The four streets round the outside stay open along the site.
	var c := site.get_center()
	var kmin := Vector2i(1 << 30, 1 << 30)
	var kmax := Vector2i(-(1 << 30), -(1 << 30))
	for k: Vector2i in d.blocks:
		kmin = Vector2i(mini(kmin.x, k.x), mini(kmin.y, k.y))
		kmax = Vector2i(maxi(kmax.x, k.x), maxi(kmax.y, k.y))
	for q: Array in [[CityPlan.AXIS_X, kmin.x, c.y], [CityPlan.AXIS_X, kmax.x + 1, c.y], [CityPlan.AXIS_Z, kmin.y, c.x], [CityPlan.AXIS_Z, kmax.y + 1, c.x]]:
		if not plan.road_open(q[0], q[1], q[2]):
			ok = false
	_t._check(ok and not (d.closed as Array).is_empty() == ((d.blocks as Array).size() > 1),
		"memorial park %s: its inner streets are closed, the four round it open" % [d.cell])


func _plan(plan: CityPlan, d: Dictionary) -> void:
	var k: Vector2i = d.blocks[0]
	var pl := Cemetery.plan_for(plan, k.x, k.y)
	var site: Rect2 = pl.site
	var grown := site.grow(0.5)
	var ok := grown.has_point(pl.gate) and absf(Cemetery.height(pl, pl.gate)) < 0.001
	for p: Vector2 in pl.road:
		if not grown.has_point(p):
			ok = false
	for key: String in ["chapel", "mausoleum"]:
		var bd: Dictionary = pl[key]
		var r := maxf(float(bd.w), float(bd.d)) * 0.5
		if not site.grow(-r * 0.5).has_point(bd.c):
			ok = false
	for t: Array in pl.trees:
		if not site.has_point(t[0]):
			ok = false
	_t._check(ok, "memorial park %s: the gate on its edge, the drive, the buildings and the trees inside" % [d.cell])
	var graves := Cemetery.graves(pl, site, 0, 1)
	var on_road := 0
	var on_building := 0
	for g: Array in graves:
		var p: Vector2 = g[1]
		if Cemetery.road_distance(pl, p) < Cemetery.ROAD_W * 0.5 + 0.5:
			on_road += 1
		if Cemetery.on_building(pl, p, 0.5):
			on_building += 1
	_t._check(graves.size() > 800 and on_road == 0 and on_building == 0,
		"memorial park %s: %d stones, none on the drive (%d) or a building (%d)" % [d.cell, graves.size(), on_road, on_building])
	# A gentle rise: nothing at the wall, its crown at H, no slope over 25 %.
	var steep := 0.0
	var edge := 0.0
	for i in 40:
		for j in 40:
			var p := site.position + Vector2(site.size.x * (float(i) + 0.5) / 40.0, site.size.y * (float(j) + 0.5) / 40.0)
			var gx := (Cemetery.height(pl, p + Vector2(0.5, 0)) - Cemetery.height(pl, p - Vector2(0.5, 0)))
			var gz := (Cemetery.height(pl, p + Vector2(0, 0.5)) - Cemetery.height(pl, p - Vector2(0, 0.5)))
			steep = maxf(steep, Vector2(gx, gz).length())
	for i in 40:
		var t := float(i) / 40.0
		for p: Vector2 in [site.position + Vector2(site.size.x * t, 0.5), site.end - Vector2(site.size.x * t, 0.5)]:
			edge = maxf(edge, Cemetery.height(pl, p))
	var top := Cemetery.height(pl, pl.crown)
	_t._check(steep < 0.25 and edge < 0.01 and top > float(pl.H) * 0.8,
		"memorial park %s: a gentle rise (crown %.1f m, steepest %.0f %%, %.2f m at the wall)" % [d.cell, top, steep * 100.0, edge])


func _chunks(city: Node3D, plan: CityPlan, d: Dictionary) -> void:
	var k: Vector2i = d.blocks[0]
	var pl := Cemetery.plan_for(plan, k.x, k.y)
	var tree := _t.get_tree()
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var lawn := chunk.get_node_or_null("CemeteryLawn")
	var body := chunk.get_node_or_null("CemeteryBody")
	var zones := 0
	for c in chunk.get_children():
		if c.is_in_group(Sanctuary.ZONE_GROUP):
			zones += 1
	var others := 0
	for c in chunk.get_children():
		if c is StaticBody3D and c != body and c.name != "StreetProps" and (c as StaticBody3D).get_child_count() > 0:
			others += 1
	_t._check(lawn != null and body != null and body.is_in_group(Sanctuary.BODY_GROUP) and zones == 1,
		"memorial park %s: the lawn, the collision in the sanctuary body, one sanctuary zone (%s %s %d)" % [k, lawn != null, body != null, zones])
	var own := plan.owned_rect(k.x, k.y).intersection(pl.site as Rect2)
	var inside := own.get_center()
	var at := chunk.global_transform * Vector3(inside.x, chunk._gy(inside.x, inside.y) + 1.5, inside.y)
	var outside := chunk.global_transform * Vector3((pl.site as Rect2).position.x - 40.0, chunk._gy(inside.x, inside.y) + 1.5, inside.y)
	var far := chunk.global_transform * Vector3((pl.site as Rect2).end.x + 60.0, chunk._gy(inside.x, inside.y) + 1.5, inside.y)
	await tree.process_frame
	_t._check(Sanctuary.contains(tree, at) and Sanctuary.segment_hits(tree, outside, at) and Sanctuary.contains(tree, at + Vector3(0, 30, 0)),
		"memorial park %s: the guns' sanctuary rule covers the park and a shot into it" % [k])
	var breakable := 0
	for rec: Dictionary in chunk.prop_records:
		var p: Vector3 = rec.get("position", Vector3.ZERO)
		if (pl.site as Rect2).has_point(Vector2(p.x, p.z)):
			breakable += 1
	_t._check(breakable == 0, "memorial park %s: nothing in it breaks (%d breakable props)" % [k, breakable])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# LOD: the zone stays; the capture records the lawn and adds no node.
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var lzones := 0
	for c in lod.get_children():
		if c.is_in_group(Sanctuary.ZONE_GROUP):
			lzones += 1
	_t._check(lzones == 1, "memorial park %s: its LOD chunk keeps the sanctuary zone" % [k])
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
	var lawn_slabs := 0
	for g: Array in cap.captured.get("ground", []):
		if (pl.site as Rect2).grow(0.1).encloses(g[0]) and absf(float(g[2]) - (CityChunk.SIDEWALK_TOP + 0.04)) < 0.01:
			lawn_slabs += 1
	_t._check(lawn_slabs >= 1 and cap.get_child_count() == 0, "memorial park %s: the far city records its lawn (%d) and builds no node" % [k, lawn_slabs])
	cap.free()
