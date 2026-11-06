extends RefCounted
## The church_sunday refcam (WorshipSunday, Worshipper, RcChurchSunday; wave 8) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the camera row (a Sunday 10:30 clear, staged by its "sunday" key); the congregation's
## hours (its day only, before and after the board's services, none on a weekday, the synagogue
## on Saturday); the site's walking points (the gate across the street wall, the forecourt on its
## paving, the door before the facade); no kerb tree or grounds tree in front of a church while the
## pass is on, and the old placement with it off; the nearest Mission church's chunk, built for
## half an hour before Mass, holds a congregation in Sunday-best rigs, none of them with nothing
## else to do than the site, and none on a weekday.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var t0 := Time.get_ticks_msec()
	var saved := [WorshipSunday.enabled, WorshipSunday.force_day, WorshipSunday.force_hour, RcChurchSunday.enabled]
	WorshipSunday.enabled = true
	RcChurchSunday.enabled = true
	_row()
	_hours()
	var plan: CityPlan = city.plan
	var s := _nearest_mission(plan)
	_check(not s.is_empty(), "rc5 church: a Mission church stands in the city")
	if not s.is_empty():
		_spots(s)
		_trees(plan, s)
		await _chunk(city, s)
	WorshipSunday.enabled = saved[0]
	WorshipSunday.force_day = saved[1]
	WorshipSunday.force_hour = saved[2]
	RcChurchSunday.enabled = saved[3]
	print("RC5_CHURCH_SUNDAY_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row := {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if String(c.get("name", "")) == "church_sunday":
				row = c
	_check(not row.is_empty() and int(row.get("sunday", 0)) == 1 and is_equal_approx(float(row.get("hour", 0)), 10.5)
		and String(row.get("weather", "")) == "clear",
		"rc5 church: the camera row is a Sunday 10:30 clear, staged by its sunday key (%s)" % str(row.keys()))


func _hours() -> void:
	var M := Worship.Kind.MISSION
	var bad: Array[String] = []
	for sd in 5:
		var first: float = WorshipSunday.services(M, sd)[0]
		if WorshipSunday.busy(M, sd, 0, first - 0.25) < 0.8:
			bad.append("seed %d: quiet a quarter hour before Mass" % sd)
		if first + 0.5 < 12.0 - WorshipSunday.ARRIVE_FROM and WorshipSunday.busy(M, sd, 0, first + 0.5) > 0.0:
			bad.append("seed %d: crowded during Mass" % sd)
		if WorshipSunday.busy(M, sd, 0, first + 1.2) < 0.5:
			bad.append("seed %d: nobody coming out after it" % sd)
		for day in range(1, 7):
			if WorshipSunday.busy(M, sd, day, first - 0.25) > 0.0:
				bad.append("seed %d: people on day %d" % [sd, day])
		if WorshipSunday.busy(M, sd, 0, 16.0) > 0.0 or WorshipSunday.busy(M, sd, 0, 6.0) > 0.0:
			bad.append("seed %d: people outside the services" % sd)
		var syn: float = WorshipSunday.services(Worship.Kind.SYNAGOGUE, sd)[0]
		if WorshipSunday.busy(Worship.Kind.SYNAGOGUE, sd, 6, syn - 0.25) < 0.8 or WorshipSunday.busy(Worship.Kind.SYNAGOGUE, sd, 0, syn - 0.25) > 0.0:
			bad.append("seed %d: the synagogue's day" % sd)
		for k in Worship.Kind.size():
			for hh in range(14, 30):
				var n := WorshipSunday.count(k, sd, WorshipSunday.holy_day(k), float(hh) * 0.5)
				if n < 0 or n > int(WorshipSunday.PEAK[k]):
					bad.append("kind %d count %d" % [k, n])
	# The services are the name board's.
	var line := WorshipBuild._service_line(M, 2)
	var h: float = WorshipSunday.services(M, 2)[0]
	var hs := "%d:%02d" % [int(h), int(round(fmod(h, 1.0) * 60.0))]
	if not line.contains(hs) or not line.contains("12:00"):
		bad.append("the board %s is not the services %s" % [line, hs])
	_check(bad.is_empty(), "rc5 church: the congregation comes on its day, before and after the board's services only (%s)" % str(bad.slice(0, 4)))


func _nearest_mission(plan: CityPlan) -> Dictionary:
	var best := {}
	var bd := INF
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var s := Worship.for_cell(plan, Vector2i(cx, cz))
			if s.is_empty() or int(s.kind) != Worship.Kind.MISSION:
				continue
			var d := (s.site as Rect2).get_center().length()
			if d < bd:
				bd = d
				best = s
	return best


func _spots(s: Dictionary) -> void:
	var p := WorshipBuild.plan_of(s)
	var ctx := {"path_x": float(p.xc)}
	var sp := WorshipSunday.spots(p, ctx)
	var front := -float(p.fz) + 0.9
	var court_ok := true
	for q: Vector2 in sp.court:
		var x0 := float(p.xc) - float(p.W) * 0.5 - 0.4
		var x1 := float(p.xc) + float(p.W) * 0.5 + float(p.arcade) + 0.4
		if q.x < x0 or q.x > x1 or q.y < front or q.y > front + 4.0:
			court_ok = false
	_check(court_ok and (sp.court as Array).size() >= 8, "rc5 church: the forecourt's spots are on its paving before the facade")
	_check((sp.gate_out as Vector2).y > 0.0 and (sp.gate_in as Vector2).y < -0.45 - 0.5 and (sp.door as Vector2).y > front
		and (sp.door as Vector2).y < front + 1.5 and (sp.street[0] as Vector2).y > 0.0,
		"rc5 church: the route crosses the street wall at the gate and ends at the door's step")


func _trees(plan: CityPlan, s: Dictionary) -> void:
	var f: Dictionary = s.frame
	var n: Vector2 = f.n
	var front := Industrial.fp(f, float(s.L) * 0.5, 0.0)
	var along := Vector2(-n.y, n.x)
	var p := WorshipBuild.plan_of(s)
	# A kerb tree before the facade's middle, on the pavement.
	var kerb := front - n * (plan.sidewalk_width - 0.8) + along * float(p.xc)
	var at := Vector3(kerb.x, 0.0, kerb.y)
	var far := front - n * (plan.sidewalk_width - 0.8) + along * (float(s.L) * 0.5 + 30.0)
	_check(RcChurchSunday.keeps_tree_off(plan, at) and not RcChurchSunday.keeps_tree_off(plan, Vector3(far.x, 0.0, far.y)),
		"rc5 church: the kerb keeps its trees off the church's front, not off the next lot's")
	RcChurchSunday.enabled = false
	var off := RcChurchSunday.keeps_tree_off(plan, at) or RcChurchSunday.front_clear(p, Vector2(float(p.xc), -2.0))
	RcChurchSunday.enabled = true
	_check(not off and RcChurchSunday.front_clear(p, Vector2(float(p.xc), -2.0)) and not RcChurchSunday.front_clear(p, Vector2(float(p.xc), -float(p.fz) - 20.0)),
		"rc5 church: the lawn before the facade is kept clear (and RC5_CHURCH=0 plants as before)")


func _chunk(city: Node3D, s: Dictionary) -> void:
	var p := WorshipBuild.plan_of(s)
	var first: float = WorshipSunday.services(int(p.kind), int(p.seed))[0]
	var cap: int = city.get("max_pedestrians")
	city.set("max_pedestrians", maxi(cap, -CityChunk.count_crowd_room(city.get_tree(), 0)) + 200)
	var counts: Array[int] = []
	var best_ok := true
	var front_tree := false
	for day: int in [0, 3]:
		WorshipSunday.force_day = day
		WorshipSunday.force_hour = first - 0.25
		var chunk: CityChunk = city._new_chunk(s.block, CityChunk.Level.FULL)
		chunk.build()
		var n := 0
		for c in chunk.get_children():
			if c is Worshipper:
				n += 1
				var w := c as Worshipper
				var name := w.model_pick.get_file().get_basename()
				if not (name in WorshipSunday.BEST) or not w.is_in_group("worshipper"):
					best_ok = false
		counts.append(n)
		if day == 0:
			var node: Node3D = null
			for c in chunk.get_children():
				if c.is_in_group("worship"):
					node = c
			front_tree = node == null
		chunk.queue_free()
		await _tree.physics_frame
		await _tree.physics_frame
	city.set("max_pedestrians", cap)
	_check(counts[0] >= 8 and counts[1] == 0 and best_ok and not front_tree,
		"rc5 church: a quarter hour before Mass its chunk holds a congregation in Sunday best, and nobody on a Wednesday (%s)" % str(counts))
