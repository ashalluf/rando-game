extends RefCounted
## Rec parks and school campuses (Parks, ParkKit, ParkGoer, ParkBall), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The roles over a window of the basin: rec parks and schools in the suburbs and midtown, only on
## plain city blocks, a school with no lots. The plans: every facility inside its site, none on
## another, at regulation size (courts, the diamond's bases, a track no longer than 400 m, a
## football field that fits inside its kerb), the pure plan the same when asked twice. A FULL chunk
## of a rec park and of a school: the ground ONE shadowless mesh on the ground shader, everything
## upright ONE casting mesh on the walls shader, the floodlight pools casting nothing, people on the
## facilities under the cap, a triangle budget. A LOD build lays no park meshes; the far city's
## capture lays the ground as slabs that never overlap (no z-fighting) and the buildings as far
## boxes. The shaders handle every kind; a jogger's oval maps back onto itself.

var _t: Node

## Triangles the kit may write for one block (a big rec park with everything is ~25k).
const KIT_BUDGET := 70000


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_kinds()
	var found := _roles(plan)
	_oval()
	for k: Vector2i in found:
		if k == Vector2i(9999, 9999):
			continue
		_full_chunk(city, plan, k)
		_lod_chunk(city, plan, k)


func _kinds() -> void:
	var src: String = (load("res://shaders/park_ground.gdshader") as Shader).code
	var ok := true
	for k in 13:
		if not (src.contains("k == %d)" % k) or src.contains("k == %d ||" % k) or src.contains("|| k == %d" % k)):
			ok = false
	_t._check(ok, "the park ground shader draws each of the 13 ground kinds")
	var wsrc: String = (load("res://shaders/park_walls.gdshader") as Shader).code
	var wok := true
	for k in ParkKit.KIND_COUNT:
		if not (wsrc.contains("k == %d)" % k) or wsrc.contains("k == %d ||" % k) or wsrc.contains("|| k == %d" % k)):
			wok = false
	_t._check(wok, "the park walls shader draws each of the kit's %d kinds" % ParkKit.KIND_COUNT)


## Returns [a rec park with the most facilities, a school with a track (or any school)].
func _roles(plan: CityPlan) -> Array[Vector2i]:
	var n := {"rec": 0, "school": 0, "high": 0, "diamond": 0, "soccer": 0, "basketball": 0, "tennis": 0, "playground": 0,
		"pool": 0, "track": 0, "football": 0, "rec_centre": 0, "wing": 0}
	var bad: Array = []
	var best_rec := Vector2i(9999, 9999)
	var best_rec_n := 0
	var school := Vector2i(9999, 9999)
	var high_found := false
	var lo: Vector2i = plan.block_index_at(Vector2(-1500.0, -3600.0))
	var hi: Vector2i = plan.block_index_at(Vector2(1500.0, 1500.0))
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			if not b.has("grounds"):
				continue
			var rect: Rect2 = b.rect
			if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY or not (int(b.district) in Parks.REC_DISTRICTS):
				bad.append("role off city ground %s" % [Vector2i(bx, bz)])
			if not plan.lots(bx, bz).is_empty():
				bad.append("lots on %s" % [Vector2i(bx, bz)])
			if b.grounds == "school" and int(b.kind) != CityPlan.BlockKind.SCHOOL:
				bad.append("school not SCHOOL %s" % [Vector2i(bx, bz)])
			var pl := Parks.plan_for(plan, bx, bz)
			n[b.grounds] += 1
			var site: Rect2 = pl.site
			var fac: Array = pl.fac
			for i in fac.size():
				var f: Dictionary = fac[i]
				var r: Rect2 = f.r
				n[f.t] = int(n.get(f.t, 0)) + 1
				if not site.grow(0.05).encloses(r):
					bad.append("%s outside its site at %s" % [f.t, Vector2i(bx, bz)])
				for j in range(i + 1, fac.size()):
					var g: Dictionary = fac[j]
					# The bleachers stand beside the track; nothing else touches.
					if r.intersection(g.r).get_area() > 0.05:
						bad.append("%s on %s at %s" % [f.t, g.t, Vector2i(bx, bz)])
				match f.t:
					"basketball":
						if absf(float(f.L) - Parks.BB_COURT.x - Parks.BB_CLEAR * 2.0) > 0.01 or (f.W as float) / float(f.n) < Parks.BB_COURT.y:
							bad.append("short court %s" % [Vector2i(bx, bz)])
					"tennis":
						if absf(float(f.L) - Parks.TEN_ENCLOSURE.x) > 0.01:
							bad.append("tennis enclosure %s" % [Vector2i(bx, bz)])
					"track":
						n.high += 1
						if float(f.lap) > 400.01 or float(f.lap) < 200.0:
							bad.append("track lap %.1f" % float(f.lap))
						if float(f.football) > 0.0:
							n.football += 1
							var hw := Parks.FOOTBALL.y * 0.5 * float(f.football)
							if hw >= float(f.R):
								bad.append("football wider than the infield")
						if not high_found:
							school = Vector2i(bx, bz)
							high_found = true
					"diamond":
						if float(f.fence) < Parks.FENCE_RADIUS.x - 0.01:
							bad.append("short fence")
			if b.grounds == "school" and school == Vector2i(9999, 9999):
				school = Vector2i(bx, bz)
			if b.grounds == "rec" and fac.size() > best_rec_n:
				best_rec_n = fac.size()
				best_rec = Vector2i(bx, bz)
			# Pure: asked again (from a cold cache), the same plan.
			Parks._cache.clear()
			var again := Parks.plan_for(plan, bx, bz)
			if again.fac.size() != fac.size() or (again.fac.size() > 0 and (again.fac[0].r as Rect2) != (fac[0].r as Rect2)):
				bad.append("plan not pure at %s" % [Vector2i(bx, bz)])
	_t._check(bad.is_empty(), "park and school plans: on city ground, no lots, inside their sites, nothing on anything, regulation sizes, pure (%s)" % [bad.slice(0, 4)])
	_t._check(n.rec >= 20 and n.school >= 3 and n.diamond >= 5 and n.basketball >= 10 and n.tennis >= 4 and n.playground >= 8 and n.pool >= 2 and n.track >= 1 and n.wing >= 3,
		"rec parks and schools across the basin (%s)" % [n])
	var out: Array[Vector2i] = [best_rec, school]
	return out


func _oval() -> void:
	var p := ParkGoer.new()
	p.oval_c = Vector2(100.0, 50.0)
	p.oval_u = Vector2(0.0, 1.0)
	p.oval_hs = 40.0
	p.oval_r = 33.0
	var worst := 0.0
	for i in 40:
		var s := p._perimeter() * float(i) / 40.0 + 0.3
		worst = maxf(worst, absf(p._oval_s(p._oval_at(s)) - s))
	_t._check(worst < 0.05, "a jogger's oval maps back onto itself (worst %.3f m)" % worst)
	p.free()


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var before := ParkKit.tris
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var kit := ParkKit.tris - before
	var role: String = plan.block(k.x, k.y).grounds
	var grounds := chunk.find_children("ParkGround", "MeshInstance3D", false, false)
	var walls := chunk.find_children("ParkWalls", "MeshInstance3D", false, false)
	_t._check(grounds.size() == 1 and (grounds[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and (grounds[0] as MeshInstance3D).material_override == Parks.ground_material(),
		"%s %s: its ground is one shadowless mesh on the park ground shader (%d)" % [role, k, grounds.size()])
	_t._check(walls.size() == 1 and (walls[0] as MeshInstance3D).material_override == Parks.walls_material()
		and (walls[0] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"%s %s: everything upright is one casting mesh on the park walls shader (%d)" % [role, k, walls.size()])
	var pools_ok := true
	var buildings := 0
	var people := 0
	for c in chunk.get_children():
		var nm := String(c.name)
		if nm.begins_with("Batch_park_pool") and (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			pools_ok = false
		if c is Building:
			buildings += 1
		if c is ParkGoer:
			people += 1
	_t._check(pools_ok and buildings == 0 and kit > 500 and kit < KIT_BUDGET,
		"%s %s: no Building on it, the floodlight pools cast nothing, the kit is %d triangles (budget %d)" % [role, k, kit, KIT_BUDGET])
	# The smoke test's crowd cap is usually spent by now, so the spawn steps are what is checked.
	var steps := Parks.people_steps(chunk, plan.block(k.x, k.y)).size()
	_t._check(people <= Parks.MAX_PEOPLE and steps >= 3, "%s %s: %d people on its facilities, %d spawn steps (at most %d people)" % [role, k, people, steps, Parks.MAX_PEOPLE])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var none := chunk.get_node_or_null("ParkGround") == null and chunk.get_node_or_null("ParkWalls") == null
	_t._check(none, "a LOD build of %s lays no park meshes" % [k])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var site: Rect2 = Parks.plan_for(plan, k.x, k.y).site
	var mine: Array[Rect2] = []
	for g: Array in cap.captured.get("ground", []):
		var r: Rect2 = g[0]
		if site.grow(0.1).encloses(r) and absf(float(g[2]) - (CityChunk.SIDEWALK_TOP + Parks.LIFT)) < 0.005:
			mine.append(r)
	var overlap := 0
	var area := 0.0
	for i in mine.size():
		area += mine[i].get_area()
		for j in range(i + 1, mine.size()):
			if mine[i].intersection(mine[j]).get_area() > 0.05:
				overlap += 1
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	_t._check(mine.size() >= 3 and overlap == 0 and area > site.get_area() * 0.6,
		"the far city captures %s's ground as %d slabs, none on another (%d overlaps), %.0f %% of the site" % [k, mine.size(), overlap, 100.0 * area / maxf(site.get_area(), 1.0)])
	_t._check((boxes.get("xforms", []) as Array).size() >= 1, "the far city captures %s's buildings or stands as far boxes" % [k])
	cap.free()
