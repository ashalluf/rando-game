extends RefCounted
## MacArthur Park from the air (MacArthurLook, the macarthur reference camera; docs/HANDOFF.md
## "MacArthur Park from the air"), for tests/smoke_test.gd. Reads the layout and the pure helpers
## only: no waiting, nothing staged.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	if not LandmarkMacArthurPark.enabled or not MacArthurLook.enabled:
		_t._check(true, "MacArthur look: off (MACARTHUR_LOOK=0 or no park), nothing to check")
		return
	var lay := LandmarkMacArthurPark.layout(plan)
	if lay.is_empty():
		_t._check(false, "MacArthur look: the park has a layout")
		return
	_water(lay)
	_palms(lay, plan)
	_trees(lay)
	_walks(lay)
	_materials(plan)


## The water grid covers the lake and only the lake, and its shore distance is 0 at the wall and
## grows inward.
func _water(lay: Dictionary) -> void:
	var lake: PackedVector2Array = lay.lake
	var bounds: Rect2 = lay.lake_bounds
	var tris := MacArthurLook.water_tris(lake, bounds, bounds.grow(2.0))
	var area := 0.0
	var outside := 0
	for t: Array in tris:
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		area += absf((b - a).cross(c - a)) * 0.5
		var m := (a + b + c) / 3.0
		if not Geometry2D.is_point_in_polygon(m, lake) and MacArthurLook.shore_distance(lake, m) > 0.3:
			outside += 1
	var want := 0.0
	var idx := Geometry2D.triangulate_polygon(lake)
	for k in range(0, idx.size(), 3):
		want += absf((lake[idx[k + 1]] - lake[idx[k]]).cross(lake[idx[k + 2]] - lake[idx[k]])) * 0.5
	_t._check(absf(area - want) < want * 0.01 and outside == 0,
		"MacArthur look: the water grid is the lake (%.0f of %.0f m2, %d cells outside)" % [area, want, outside])
	var wall := MacArthurLook.shore_distance(lake, lake[3])
	var mid := MacArthurLook.shore_distance(lake, lay.fountain)
	_t._check(wall < 0.5 and mid > 15.0, "MacArthur look: shore distance 0 at the wall (%.2f), deep at the fountain (%.1f m)" % [wall, mid])


## The lake's palms: off the water and the promenade, and no longer an even picket.
func _palms(lay: Dictionary, plan: CityPlan) -> void:
	var bad := 0
	var ring: Array[Vector2] = []
	for p: Vector2 in lay.palms:
		if LandmarkMacArthurPark.in_lake(lay, p, LandmarkMacArthurPark.COPING_W + LandmarkMacArthurPark.PROMENADE_W + 0.9):
			bad += 1
		elif LandmarkMacArthurPark.in_lake(lay, p, LandmarkMacArthurPark.PALM_RING_OFFSET + MacArthurLook.PALM_ACROSS + 3.5):
			ring.append(p)
	# Nearest-neighbour spacing round the ring: an even picket has every gap the same.
	var gaps: Array[float] = []
	for p in ring:
		var best := INF
		for q in ring:
			if q != p:
				best = minf(best, p.distance_to(q))
		gaps.append(best)
	var mean := 0.0
	for g in gaps:
		mean += g
	mean /= maxf(1.0, gaps.size())
	var dev := 0.0
	for g in gaps:
		dev += (g - mean) * (g - mean)
	dev = sqrt(dev / maxf(1.0, gaps.size()))
	_t._check(bad == 0 and ring.size() > 20 and dev > mean * 0.2,
		"MacArthur look: the lake's palms keep off the walk (%d bad) and stand irregularly (%d, spacing %.1f +- %.1f m)" % [bad, ring.size(), mean, dev])
	var again := LandmarkMacArthurPark._palm_spots(lay, plan.seed)
	_t._check(again == lay.palms, "MacArthur look: the palms are hashes (the same twice)")


## Shade trees: about three times the old park's, never closer than TREE_SPACING, off the water.
func _trees(lay: Dictionary) -> void:
	var trees: Array = lay.trees
	var close := 0
	var wet := 0
	for i in trees.size():
		var p: Vector2 = trees[i]
		if LandmarkMacArthurPark.in_lake(lay, p, LandmarkMacArthurPark.PALM_RING_OFFSET):
			wet += 1
		for j in range(i + 1, trees.size()):
			if p.distance_to(trees[j]) < MacArthurLook.TREE_SPACING - 0.01:
				close += 1
	var lawn := 0.0
	for half: Rect2 in [lay.north_in, lay.south_in]:
		lawn += half.size.x * half.size.y
	var old := int(lawn / 1000.0 * LandmarkMacArthurPark.TREES_PER_1000)
	_t._check(trees.size() >= int(old * 1.8) and close == 0 and wet == 0,
		"MacArthur look: %d shade trees (the old park %d), %d too close, %d by the water" % [trees.size(), old, close, wet])


## The walks across the north lawn stay on it.
func _walks(lay: Dictionary) -> void:
	var extra := MacArthurLook.extra_paths(lay)
	var out := 0
	for path: Dictionary in extra:
		for p: Vector2 in (path.pts as PackedVector2Array):
			if not (lay.north_in as Rect2).grow(0.5).has_point(p):
				out += 1
	_t._check(extra.size() >= 3 and out == 0, "MacArthur look: %d walks cross the north lawn, %d points off it" % [extra.size(), out])


## One lawn material near and far, worn; the lake in its park look.
func _materials(plan: CityPlan) -> void:
	var a := MacArthurLook.lawn_material(plan.seed) as ShaderMaterial
	var b := MacArthurLook.lawn_material(plan.seed) as ShaderMaterial
	_t._check(a != null and a == b and absf(float(a.get_shader_parameter("wear_amount")) - MacArthurLook.LAWN_WEAR) < 0.001,
		"MacArthur look: the park's lawn is one worn material")
	var lake := LandmarkMacArthurPark.lake_material(LandmarkMacArthurPark.layout(plan))
	var src := (lake.shader as Shader).code
	_t._check(float(lake.get_shader_parameter("shore_look")) > 0.5 and src.contains("cs_out(lb)") and src.contains("UV2.x"),
		"MacArthur look: the lake is in its park look (shore depth, linear colour)")
