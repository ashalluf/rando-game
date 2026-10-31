extends RefCounted
## Los Angeles' named hills (LaHills, LaHillsBuild; docs/HANDOFF.md "Los Angeles' hills"): checks
## for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var lh: LaHills = plan.macro.la_hills
	_t._check(LaHills.enabled and lh != null and lh.hills().size() >= 7,
		"la hills: the table is built (%d hills)" % [lh.hills().size() if lh else 0])
	if lh == null:
		return
	_bunker_hill(plan)
	_flat_basin(plan, lh)
	_grades(plan, lh)
	_landmarks_level(plan, lh)
	_corridors(plan, lh)
	_stairway_chunk(city, plan, lh)


## Bunker Hill: the crest along Grand stands 18-32 m over the plain, Hill St at its foot is near the
## plain, Pershing Square and Broadway are the plain, and the downtown towers stand on the ground.
func _bunker_hill(plan: CityPlan) -> void:
	var m := plan.macro
	var crest := m.relief_at(Vector2(2611.0, -403.0))
	var foot := m.relief_at(Vector2(2866.0, -403.0))
	var square := m.relief_at(Vector2(2800.0, 103.0))
	var broadway := m.relief_at(Vector2(2991.0, -403.0))
	_t._check(crest > 18.0 and crest < 32.0 and foot < 6.0 and square < 0.5 and broadway < 0.5,
		"la hills: Bunker Hill's crest at Grand / 3rd %.1f m over Hill St %.1f, Pershing Square %.1f, Broadway %.1f" % [crest, foot, square, broadway])
	var worst := 0.0
	for lm: Dictionary in LandmarkDowntown.entries():
		var a: Vector2 = lm.anchor
		worst = maxf(worst, absf(LaHills.landmark_lift(plan, a) - m.relief_at(a)))
	_t._check(worst < 0.05, "la hills: every downtown tower is lifted onto the ground it stands on (worst %.3f m)" % worst)


## Away from the hills the basin is untouched: no lift anywhere outside the hills' boxes.
func _flat_basin(plan: CityPlan, lh: LaHills) -> void:
	var lifted := 0
	var n := 0
	var x := -2000.0
	while x <= 6000.0:
		var z := -3000.0
		while z <= 6500.0:
			var p := Vector2(x, z)
			var inside := false
			for hl: Dictionary in lh.hills():
				if (hl.box as Rect2).has_point(p):
					inside = true
			if not inside:
				n += 1
				if lh.lift_raw(p) != 0.0:
					lifted += 1
			z += 97.0
		x += 101.0
	_t._check(n > 3000 and lifted == 0, "la hills: the rest of the basin stays the plain (%d of %d samples lifted)" % [lifted, n])


## Every street stretch over a hill: a car can drive it (STAIR_GRADE at most) or it is a stairway,
## closed to cars; there are steep streets and there are stairways.
func _grades(plan: CityPlan, lh: LaHills) -> void:
	var stairs := 0
	var steep := 0
	var bad: Array[String] = []
	for hl: Dictionary in lh.hills():
		var box: Rect2 = hl.box
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			var other := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
			var i0 := plan._index_at(axis, box.position.x if axis == CityPlan.AXIS_X else box.position.y)
			var i1 := plan._index_at(axis, box.end.x if axis == CityPlan.AXIS_X else box.end.y) + 1
			var k0 := plan._index_at(other, box.position.y if axis == CityPlan.AXIS_X else box.position.x)
			var k1 := plan._index_at(other, box.end.y if axis == CityPlan.AXIS_X else box.end.x) + 1
			for i in range(i0, i1 + 1):
				for k in range(k0, k1):
					var st := LaHills.stretch(plan, axis, i, k)
					if not st.has("near"):
						continue
					var mid := (float(st.s0) + float(st.s1)) * 0.5
					var open := plan.road_open(axis, i, mid)
					if LaHills.is_stairs(plan, axis, i, k):
						stairs += 1
						if open:
							bad.append("stairs open %d %d %d" % [axis, i, k])
					elif open:
						if float(st.grade) > LaHills.STAIR_GRADE + 0.001:
							bad.append("%s %.0f%%" % [plan.road_name(axis, i), float(st.grade) * 100.0])
						if float(st.grade) > 0.15:
							steep += 1
	_t._check(bad.is_empty() and stairs >= 10 and steep >= 40,
		"la hills: %d streets steeper than 15 %% and none over %.0f %%, %d stairways closed to cars %s" % [steep, LaHills.STAIR_GRADE * 100.0, stairs, bad.slice(0, 4)])


## Every landmark on a hill still stands on level ground: its disc holds the hill's lift.
func _landmarks_level(plan: CityPlan, lh: LaHills) -> void:
	var worst := 0.0
	var worst_id := ""
	var n := 0
	for lm: Dictionary in Landmarks.all():
		if lm.has("flat_rect") or lm.has("area"):
			continue
		var a: Vector2 = lm.anchor
		if lh.lift_raw(a) < 1.0:
			continue
		n += 1
		var r: float = minf(float(lm.radius), 60.0) + 25.0
		var h0 := lh.lift(a, 0.0)
		for d: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
			var e := absf(lh.lift(a + d, 0.0) - h0)
			if e > worst:
				worst = e
				worst_id = lm.id
	_t._check(n >= 8 and worst < 0.6, "la hills: %d landmarks on the hills stand level (worst %.2f m, %s)" % [n, worst, worst_id])


## The freeways' decks, the river and the light rail keep off the hills.
func _corridors(plan: CityPlan, lh: LaHills) -> void:
	var fw := 0.0
	for fr in plan.macro.freeway.routes:
		for q: Vector2 in (fr.points as PackedVector2Array):
			fw = maxf(fw, lh.lift_raw(q))
	var rv := 0.0
	if plan.macro.river:
		for q: Vector2 in plan.macro.river.pts:
			rv = maxf(rv, lh.lift_raw(q))
	var rail := 0.0
	var lr := LightRail.of(plan)
	if lr:
		for q: Vector2 in lr.pts:
			rail = maxf(rail, lh.lift_raw(q))
	_t._check(fw < 1.0 and rv == 0.0 and rail < 0.5,
		"la hills: the freeways (%.2f m), the river (%.2f) and the light rail (%.2f) keep off the hills" % [fw, rv, rail])


## A chunk that owns a stairway builds its flight, with ground under it; off, the old road.
func _stairway_chunk(city: Node3D, plan: CityPlan, lh: LaHills) -> void:
	var found := Vector3i(-1, 0, 0)
	for hl: Dictionary in lh.hills():
		if hl.id != "echo_park" and hl.id != "bunker_hill":
			continue
		var box: Rect2 = hl.box
		var i0 := plan._index_at(CityPlan.AXIS_X, box.position.x)
		var i1 := plan._index_at(CityPlan.AXIS_X, box.end.x) + 1
		var k0 := plan._index_at(CityPlan.AXIS_Z, box.position.y)
		var k1 := plan._index_at(CityPlan.AXIS_Z, box.end.y) + 1
		for i in range(i0, i1 + 1):
			for k in range(k0, k1):
				if found.x < 0 and LaHills.is_stairs(plan, CityPlan.AXIS_X, i, k):
					found = Vector3i(0, i, k)
	_t._check(found.x == 0, "la hills: a stairway on an avenue to build")
	if found.x != 0:
		return
	var st := LaHills.stretch(plan, CityPlan.AXIS_X, found.y, found.z)
	var chunk: CityChunk = city._new_chunk(Vector2i(found.y - 1, found.z), CityChunk.Level.FULL)
	chunk.build()
	var stairs := chunk.get_node_or_null("HillStairs") as MeshInstance3D
	var rise := absf(float(st.h1) - float(st.h0))
	var span := stairs.get_aabb().size.y if stairs and stairs.mesh else 0.0
	_t._check(stairs != null and span > rise * 0.7,
		"la hills: chunk (%d, %d) builds the stairway up %s (%.1f m of flight for a %.1f m rise)" % [found.y - 1, found.z, plan.road_name(CityPlan.AXIS_X, found.y), span, rise])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
