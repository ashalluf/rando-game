extends RefCounted
## The valley golf course (GolfCourse, GolfBuild, GolfFar, GolfLife, Golfer), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The site snapped to its roads, the roads inside it closed and its blocks the course's (no lots).
## The layout: nine holes inside the course, par 30-36, corridors apart, every pin on its green, no
## bunker in a green, the path off the greens, the creek falling to the pond, the same layout when
## asked twice and on another seed. A FULL chunk: ONE shadowless turf mesh on the turf shader with
## collision, everything upright ONE mesh on the park walls material, a triangle budget; the ground
## the same on both sides of a chunk border (the binned fields). A LOD chunk: the turf, no props,
## no golfers. The capture records the rough's colour; GolfFar adds turf boxes and canopies. The
## golfers' poses move the bones; the life's placement is pure and inside the course.

var _t: Node

## Turf triangles a FULL chunk may draw (a 1.6 m grid over the biggest valley block is ~16k).
const TURF_BUDGET := 40000


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var lay := GolfCourse.layout(plan)
	_t._check(not lay.is_empty(), "the golf course is laid out on the city's plan")
	if lay.is_empty():
		return
	_site(plan, lay)
	_layout(plan, lay)
	_pure(plan)
	_shaders()
	_life(lay)
	var club: Rect2 = lay.club
	var k_club: Vector2i = plan.chunk_index_at(club.get_center())
	var g1: Vector2 = ((lay.holes as Array)[0] as Dictionary).green.c
	var k_green: Vector2i = plan.chunk_index_at(g1)
	_full_chunk(city, plan, lay, k_green)
	_border(city, plan, lay, plan.chunk_index_at((lay.course as Rect2).get_center()))
	_lod_chunk(city, plan, k_club)
	_capture(city, plan, lay, k_green)
	await _golfer(city, lay)


func _site(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var r: Rect2 = lay.rect
	_t._check(int(s.ix1) - int(s.ix0) >= 4 and int(s.iz1) - int(s.iz0) >= 4 and r.size.x > 500.0 and r.size.y > 450.0,
		"golf: the site is snapped to whole blocks (%d x %d blocks, %.0f x %.0f m)" % [int(s.ix1) - int(s.ix0), int(s.iz1) - int(s.iz0), r.size.x, r.size.y])
	var inner_x := int(s.ix0) + 1
	var mid_z := r.get_center().y
	var edge_open := plan.road_open(CityPlan.AXIS_X, int(s.ix0), mid_z) and plan.road_open(CityPlan.AXIS_Z, int(s.iz1), r.get_center().x)
	_t._check(not plan.road_open(CityPlan.AXIS_X, inner_x, mid_z) and edge_open,
		"golf: the roads inside the site are closed, the boundary roads open")
	var lots := 0
	var claimed := true
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			lots += plan.lots(ix, iz).size()
			if String(plan.block(ix, iz).get("site", "")) != GolfCourse.ID:
				claimed = false
	_t._check(claimed and lots == 0, "golf: every block of the site is the course's, with no lots (%d)" % lots)


func _layout(plan: CityPlan, lay: Dictionary) -> void:
	var course: Rect2 = lay.course
	var holes: Array = lay.holes
	var par := 0
	var yards := 0
	var inside := true
	var pins := true
	var bunkers_ok := true
	var path_ok := true
	var sub := GolfCourse.gather(lay, lay.rect)
	for h: Dictionary in holes:
		par += int(h.par)
		yards += int(h.yards)
		for p: Vector2 in (h.pts as PackedVector2Array):
			if not course.grow(1.0).has_point(p):
				inside = false
		if GolfCourse.ellipse_sdf(h.green, h.pin) > -0.5:
			pins = false
		for bk: Dictionary in h.bunkers:
			if GolfCourse.ellipse_sdf(h.green, bk.c) < 0.0 or GolfCourse.bunker_sdf(bk, (h.green as Dictionary).c) < 0.0:
				bunkers_ok = false
		if GolfCourse.field(sub, (h.green as Dictionary).c)[5] < GolfCourse.COLLAR:
			path_ok = false
	_t._check(holes.size() == 9 and par >= 30 and par <= 36 and yards > 1700, "golf: nine holes, par %d, %d yards" % [par, yards])
	_t._check(inside, "golf: every tee, bend and green is inside the course")
	var gap := GolfCourse.hole_gaps(holes.map(func(h: Dictionary) -> PackedVector2Array: return h.pts))
	_t._check(gap > 30.0, "golf: no two holes' lines come closer than 30 m (%.1f)" % gap)
	_t._check(pins and bunkers_ok and path_ok, "golf: every pin on its green, no bunker in a green, the cart path off every green")
	var levels: PackedFloat32Array = lay.creek_levels
	var falls := true
	for k in levels.size() - 1:
		if levels[k + 1] > levels[k] + 1e-4:
			falls = false
	var pond_low := true
	for p: Vector2 in (lay.pond as PackedVector2Array):
		if plan.macro.relief_at(p) + CityChunk.SIDEWALK_TOP < float(lay.pond_level):
			pond_low = false
	_t._check(falls and absf(levels[levels.size() - 1] - float(lay.pond_level)) < 1e-3 and pond_low,
		"golf: the creek falls all the way to the pond, the pond's surface under the ground round it")
	var trees: Array = lay.trees
	var clear := true
	for tr: Array in trees:
		if int(tr[1]) == 3:
			continue
		var f := GolfCourse.field(sub, tr[0])
		if f[0] < 0.0 or f[1] < 0.0 or f[2] < 0.0 or f[4] < 0.0 or f[5] < 0.0:
			clear = false
	_t._check(trees.size() > 150 and clear, "golf: %d trees, none on a fairway, green, bunker, water or the path" % trees.size())


func _pure(plan: CityPlan) -> void:
	var p2 := CityPlan.new()
	p2.seed = plan.seed
	p2.macro = plan.macro
	var a := GolfCourse.layout(plan)
	var b := GolfCourse.layout(p2)
	var same := not b.is_empty() and (a.holes as Array).size() == (b.holes as Array).size()
	if same:
		for i in (a.holes as Array).size():
			var ha: Dictionary = a.holes[i]
			var hb: Dictionary = b.holes[i]
			if ha.pin != hb.pin or ha.yards != hb.yards or (ha.bunkers as Array).size() != (hb.bunkers as Array).size():
				same = false
	_t._check(same and (a.trees as Array).size() == (b.trees as Array).size(), "golf: the layout is the same when worked out again from the seed")


func _shaders() -> void:
	for path: String in ["res://shaders/golf_turf.gdshader", "res://shaders/golf_flag.gdshader"]:
		var sh := load(path) as Shader
		_t._check(sh != null and sh.get_shader_uniform_list().size() > 0 and sh.code.contains("color_space.gdshaderinc"),
			"golf: %s loads and works through the colour-space include" % path.get_file())


func _life(lay: Dictionary) -> void:
	var course: Rect2 = lay.course
	var groups := GolfLife.groups(lay)
	var inside := true
	var people := 0
	for g: Dictionary in groups:
		for m: Array in g.members:
			people += 1
			if not course.grow(2.0).has_point(m[0]):
				inside = false
	var again := GolfLife.groups(lay)
	_t._check(groups.size() >= 3 and inside and again.size() == groups.size(), "golf: %d groups (%d golfers) on the course, the same when asked again" % [groups.size(), people])
	_t._check(GolfLife.range_spots(lay).size() >= 4 and GolfLife.sprinkler_spots(lay).size() > 30,
		"golf: golfers on the range's bays and the practice green, sprinkler heads along the fairways")
	var tris := GolfLife.cart_mesh().get_faces().size() / 3
	_t._check(tris > 100 and tris < 3000, "golf: the cart's model is %d triangles" % tris)


func _full_chunk(city: Node3D, plan: CityPlan, lay: Dictionary, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var turf := chunk.find_children("GolfTurf", "MeshInstance3D", false, false)
	var ok := turf.size() == 1 and (turf[0] as MeshInstance3D).material_override == GolfBuild.turf_material() \
		and (turf[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tris := 0
	if turf.size() == 1:
		tris = ((turf[0] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_t._check(ok and tris > 500 and tris < TURF_BUDGET, "golf %s: the turf is one shadowless mesh on the turf shader (%d triangles, budget %d)" % [k, tris, TURF_BUDGET])
	var shape := chunk.find_children("GolfTurfShape", "CollisionShape3D", true, false)
	_t._check(shape.size() == 1, "golf %s: the turf has its collision" % k)
	var walls := chunk.find_children("GolfWalls", "MeshInstance3D", false, false)
	_t._check(walls.size() == 1 and (walls[0] as MeshInstance3D).material_override == Parks.walls_material(),
		"golf %s: everything upright is one mesh on the park walls material" % k)
	var flags := chunk.find_children("Batch_golf_flag", "MultiMeshInstance3D", true, false)
	var trees := 0
	for c in chunk.get_children():
		if String(c.name).begins_with("Batch_tree_") or String(c.name).begins_with("Batch_hill_tree_"):
			trees += 1
	_t._check(flags.size() == 1 and trees >= 1, "golf %s: the flag batch is there (%d) and the trees are planted (%d batches)" % [k, flags.size(), trees])
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	_t._check(buildings == 0, "golf %s: no Building stands on the course" % k)
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## The ground either side of the border between chunk `k` and the one east of it: the same height
## from both chunks' states at every point along it (the fields are binned per chunk).
func _border(city: Node3D, plan: CityPlan, lay: Dictionary, k: Vector2i) -> void:
	var a: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	a.build()
	var b: CityChunk = city._new_chunk(k + Vector2i(1, 0), CityChunk.Level.FULL)
	b.build()
	var worst := 0.0
	var tested := 0
	if a.has_meta("golf") and b.has_meta("golf"):
		var ra := a.owned_rect()
		var x := ra.end.x
		for i in 40:
			var z := lerpf(ra.position.y, ra.end.y, (float(i) + 0.5) / 40.0)
			var p := Vector2(x, z)
			if not (lay.walk as Rect2).has_point(p):
				continue
			var ha := GolfBuild.ground(a, a.get_meta("golf"), p)
			var hb := GolfBuild.ground(b, b.get_meta("golf"), p)
			worst = maxf(worst, absf(ha - hb))
			tested += 1
	_t._check(tested > 10 and worst < 0.02, "golf %s: the ground meets across the chunk border (%d points, worst %.3f m)" % [k, tested, worst])
	for c: CityChunk in [a, b]:
		c.get_parent().remove_child(c)
		c.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var turf := chunk.find_children("GolfTurf", "MeshInstance3D", false, false)
	var golfers := 0
	for c in chunk.get_children():
		if c is Golfer:
			golfers += 1
	_t._check(turf.size() == 1 and chunk.get_node_or_null("GolfWalls") == null and golfers == 0,
		"golf %s: a LOD build lays the turf, no props, no golfers" % k)
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _capture(city: Node3D, plan: CityPlan, lay: Dictionary, k: Vector2i) -> void:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var rough := false
	for g: Array in cap.captured.get("ground", []):
		if (g[3] as Color).is_equal_approx(GolfFar.ROUGH_FAR):
			rough = true
	_t._check(rough, "golf %s: the far city's capture records the rough's colour for the plate" % k)
	var work := {"xforms": [], "colors": [], "customs": [], "veg": [], "veg_colors": [], "veg_custom": []}
	GolfFar.add(plan, k, cap, work)
	_t._check((work.xforms as Array).size() >= 1 and (work.veg as Array).size() >= 1,
		"golf %s: the far city draws its turf (%d boxes) and its trees (%d canopies)" % [k, (work.xforms as Array).size(), (work.veg as Array).size()])
	cap.free()


func _golfer(city: Node3D, lay: Dictionary) -> void:
	var g := Golfer.new()
	var h: Dictionary = (lay.holes as Array)[0]
	var at: Vector2 = ((h.tees as Array)[0] as Dictionary).c
	g.setup_golfer(at, 140.0, ((h.tees as Array)[0] as Dictionary).u, Golfer.Role.DRIVE, 1234)
	city.add_child(g)
	await _t.get_tree().process_frame
	var skel: Skeleton3D = g._skel
	var moved := false
	if skel != null and g._poses.has("top"):
		g.set_physics_process(false)
		var b := skel.find_bone("RightHand")
		g._apply_pose("", "", 0.0)
		var before := skel.get_bone_global_pose(b).origin
		g._pose_at(4.3)
		var top := skel.get_bone_global_pose(b).origin
		# The hands go from by the thighs to over the right shoulder: half a metre and more.
		moved = before.distance_to(top) / g._skel_unit > 0.4
	_t._check(skel == null or moved, "golf: a golfer's swing moves the bones (the top of the backswing)")
	g._scare(g.global_position + Vector3(5.0, 0.0, 0.0))
	_t._check(g._fled or skel == null, "golf: a frightened golfer drops the stance and runs")
	g.queue_free()
