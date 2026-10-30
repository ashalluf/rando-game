extends RefCounted
## Footbridges (Footbridges, FootbridgeKit, FootbridgeBuild; docs/HANDOFF.md "Footbridges"): checks
## for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var area := Rect2(Vector2(-2000.0, -2600.0), Vector2(6000.0, 6600.0))
	var all := Footbridges.near(plan, area)
	var kinds := [0, 0]
	for b in all:
		kinds[int(b.kind)] += 1
	_t._check(kinds[0] >= 4 and kinds[1] >= 3,
		"footbridges: boulevard and freeway bridges on the default seed (%d boulevard, %d freeway)" % kinds)
	_pure(plan, area, all)
	_owned_once(plan, all)
	var worst := ""
	for b in all:
		var why := _sound(plan, b)
		if why != "":
			worst = "%s: %s" % [b.id, why]
			break
	_t._check(worst == "", "footbridges: clearances, stairs a rise at a time to the ground, landings on the pavement, towers off the deck and roads (%s)" % worst)
	_kit(all)
	var bl: Dictionary = {}
	var fr: Dictionary = {}
	for b in all:
		if bl.is_empty() and int(b.kind) == Footbridges.Kind.BOULEVARD:
			bl = b
		if fr.is_empty() and int(b.kind) == Footbridges.Kind.FREEWAY:
			fr = b
	if not bl.is_empty():
		_chunk(city, plan, bl)
	if not fr.is_empty():
		_chunk(city, plan, fr)
		_capture(city, plan, fr)
	_switch(plan, area)


## The same question twice gives the same bridges, and a smaller rect a subset of them.
func _pure(plan: CityPlan, area: Rect2, all: Array[Dictionary]) -> void:
	var again := Footbridges.near(plan, area)
	var ids := {}
	for b in all:
		ids[b.id] = b
	var same := again.size() == all.size()
	for b in again:
		same = same and ids.has(b.id) and (ids[b.id].c as Vector2).is_equal_approx(b.c) and is_equal_approx(float(ids[b.id].y), float(b.y))
	var sub_ok := true
	if not all.is_empty():
		var first: Dictionary = all[0]
		var small := Footbridges.near(plan, Rect2(first.c, Vector2.ZERO).grow(5.0))
		var found := false
		for b in small:
			found = found or b.id == first.id
		sub_ok = found
	_t._check(same and sub_ok, "footbridges: placement is pure (the same bridges twice, found again from a 10 m rect)")


## Each bridge is built by exactly one chunk: the one whose owned rect holds its span's centre.
func _owned_once(plan: CityPlan, all: Array[Dictionary]) -> void:
	var bad := ""
	for b in all:
		var k := plan.chunk_index_at(b.c)
		var owners := 0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for o in Footbridges.owned_by(plan, k.x + dx, k.y + dz):
					if o.id == b.id:
						owners += 1
		if owners != 1:
			bad = "%s %d owners" % [b.id, owners]
			break
	_t._check(bad == "", "footbridges: every bridge has exactly one owning chunk (%s)" % bad)


## What a bridge must be: walkway clearance over what it crosses, every flight's risers summing to
## its drop and the last one ending on the ground, landings on the pavement's back half (boulevards)
## or towers clear of the deck and on corridor ground (freeways).
func _sound(plan: CityPlan, b: Dictionary) -> String:
	var depth: float = Footbridges.DEPTH[int(b.form)]
	var y: float = b.y
	if int(b.kind) == Footbridges.Kind.BOULEVARD:
		if y - depth - float(b.road_top) < Footbridges.CLEARANCE_ROAD - 0.01:
			return "clearance %.2f over the road" % (y - depth - float(b.road_top))
		var w := plan.road_width(int(b.axis), int(b.index))
		var pos := plan.road_pos(int(b.axis), int(b.index))
		var dir: Vector2 = b.dir
		for e: Dictionary in b.ends:
			var lc: Vector2 = e.landing.c
			var t := absf(lc.dot(dir) - pos)
			if t - Footbridges.LANDING_D * 0.5 < w * 0.5 + 0.5 or t + Footbridges.LANDING_D * 0.5 > w * 0.5 + plan.sidewalk_width + 0.01:
				return "landing %.2f m from the road's centre (road half %.1f)" % [t, w * 0.5]
	else:
		if y - depth - float(b.deck) < Footbridges.CLEARANCE_DECK - 0.01:
			return "clearance %.2f over the deck" % (y - depth - float(b.deck))
		var fw: Freeway = plan.macro.freeway
		for e: Dictionary in b.ends:
			var tw: Dictionary = e.tower
			var tc: Vector2 = tw.c
			var r := Footbridges._turned_rect(tc, tw.out, tw.along, float(tw.d) * 0.5, float(tw.len) * 0.5)
			if fw.blocks_rect(r, 0.5):
				return "a tower under its deck"
			var blk := plan.block_index_at(tc)
			if not (plan.block(blk.x, blk.y).rect as Rect2).grow(-plan.sidewalk_width).encloses(r):
				return "a tower off its block's inner ground"
	for e: Dictionary in b.ends:
		var st: Dictionary = e.stair
		var level := y
		var flights: Array = st.flights
		for fi in flights.size():
			var f: Dictionary = flights[fi]
			var top: Vector3 = f.top
			if absf(top.y - level) > 0.01:
				return "flight %d starts %.2f m off its landing" % [fi, top.y - level]
			if float(f.rise) > Footbridges.RISER + 0.001 or float(f.rise) < 0.12:
				return "riser %.3f" % f.rise
			level = top.y - float(f.rise) * float(f.n)
		if absf(level - float(e.ground)) > 0.01:
			return "the stair ends %.2f m off the ground" % (level - float(e.ground))
	return ""


## The kit: a FULL bridge is real geometry with collision; a LOD one is a fraction of it.
func _kit(all: Array[Dictionary]) -> void:
	var worst_full := 0
	var worst_ratio := 0.0
	var boxes_ok := true
	for b in all:
		var c: Vector2 = b.c
		var o := Vector3(c.x, 0.0, c.y)
		var boxes: Array = []
		var full := FootbridgeKit.build(b, o, FootbridgeKit.Detail.FULL, boxes)
		var lod := FootbridgeKit.build(b, o, FootbridgeKit.Detail.LOD)
		worst_full = maxi(worst_full, full.triangles)
		worst_ratio = maxf(worst_ratio, float(lod.triangles) / maxf(float(full.triangles), 1.0))
		boxes_ok = boxes_ok and boxes.size() >= 12
		for bx: Array in boxes:
			var size: Vector3 = bx[1]
			boxes_ok = boxes_ok and size.x > 0.0 and size.y > 0.0 and size.z > 0.0 and (bx[0] as Vector3).length() < 80.0
	_t._check(worst_full > 2000 and worst_full < 16000 and worst_ratio < 0.6 and boxes_ok,
		"footbridges: the kit builds each bridge in one mesh (worst %d triangles, LOD at most %.0f %% of it) with box collision" % [worst_full, worst_ratio * 100.0])
	var mat := FootbridgeKit.material()
	_t._check(mat.shader != null and mat.get_shader_parameter("tag_atlas") != null and mat == FootbridgeKit.material(),
		"footbridges: one shared material on shaders/footbridge.gdshader with the street wear tag atlas")


## The owning FULL chunk builds the bridge: its pivot, mesh, body and lamp; every chunk it touches
## collapses its own planting under the stairs and the span.
func _chunk(city: Node3D, plan: CityPlan, b: Dictionary) -> void:
	var k := plan.chunk_index_at(b.c)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var pivot := chunk.get_node_or_null("Footbridge_" + String(b.id)) as Node3D
	var mesh := pivot.get_node_or_null("Mesh") as MeshInstance3D if pivot else null
	var body := pivot.get_node_or_null("Body") as StaticBody3D if pivot else null
	var shapes := body.get_child_count() if body else 0
	var lamps := 0
	if pivot:
		for c in pivot.get_children():
			if c.is_in_group("lamp_light"):
				lamps += 1
	_t._check(pivot != null and mesh != null and mesh.mesh != null and body != null and body.collision_layer == 1 and body.collision_mask == 0 and shapes >= 12 and lamps == 1,
		"footbridges: chunk %s builds %s - a mesh, a body of %d boxes on the world layer, a lamp" % [k, b.id, shapes])
	# Nothing planted in the clear rects stays drawn.
	var rects: Array[Rect2] = []
	for nb in Footbridges.near(plan, chunk.owned_rect()):
		for r: Rect2 in nb.clear:
			rects.append(r)
	var left := 0
	for c in chunk.get_children():
		if not (c is MultiMeshInstance3D) or not String(c.name).begins_with("Batch_"):
			continue
		var key := String(c.name).trim_prefix("Batch_")
		if key == "lod_box" or key == "lamp_pool" or chunk._batch.tilt_keys.has(key):
			continue
		var mm := (c as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		var data: Dictionary = chunk._batch._batches.get(key, {})
		for xf: Transform3D in data.get("xforms", []):
			if xf.basis.get_scale().x < 0.01:
				continue
			for r in rects:
				if r.has_point(Vector2(xf.origin.x, xf.origin.z)):
					left += 1
					break
	_t._check(left == 0 and chunk.has_meta("footbridge_cleared"),
		"footbridges: chunk %s keeps its trees and street furniture off the stairs and the span (%d left, %d collapsed)" % [k, left, int(chunk.get_meta("footbridge_cleared", -1))])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# A LOD build draws it with no body or lamp.
	var lodc: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lodc.build()
	var lp := lodc.get_node_or_null("Footbridge_" + String(b.id))
	_t._check(lp != null and lp.get_node_or_null("Mesh") != null and lp.get_node_or_null("Body") == null,
		"footbridges: a LOD build of chunk %s draws %s with no collision" % [k, b.id])
	lodc.get_parent().remove_child(lodc)
	lodc.free()


## The far city's capture records far boxes (plain, no windows) for the span and the towers.
func _capture(city: Node3D, plan: CityPlan, b: Dictionary) -> void:
	var k := plan.chunk_index_at(b.c)
	var on := _captured_boxes(city, plan, k)
	Footbridges.enabled = false
	var off := _captured_boxes(city, plan, k)
	Footbridges.enabled = true
	_t._check(on - off == 3, "footbridges: the far city captures the span and both towers of %s as far boxes (%d)" % [b.id, on - off])


func _captured_boxes(city: Node3D, plan: CityPlan, k: Vector2i) -> int:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var n := 0
	var lod: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	for col: Color in lod.get("custom", []):
		if is_equal_approx(col.a, 1.0):
			n += 1
	cap.free()
	return n


## FOOTBRIDGES=0: none.
func _switch(plan: CityPlan, area: Rect2) -> void:
	Footbridges.enabled = false
	var none := Footbridges.near(plan, area).is_empty()
	Footbridges.enabled = true
	_t._check(none, "footbridges: switched off (FOOTBRIDGES=0) there are none")
