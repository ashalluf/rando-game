extends RefCounted
## THE PIT, the boardwalk's skate park (SkatePark, SkateParkLife, SkaterPerson) for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Checks: the pool
## and the snake run are cut inside the high deck, clear of each other and of the step; the street
## pieces and the mini ramp stand on the terrace clear of each other; the surface the lines ride
## is the one the concrete is built from (floor, deck, terrace, stairs, the mini ramp's lip); every
## line loops, never jumps, never goes under the concrete, rides on it where it is not in the air,
## has its airs and kickflips (a kickflip down the stair set from the deck to the terrace); the
## SKATE_PARK=0 switch builds the old boxes. In the city: the boardwalk's chunk builds the park
## with its collision (rays land on the pool's floor, the deck and the terrace), the riders follow
## the clock, a knocked skater turns into a live person, gunfire wakes the nearest people.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_layout()
	_lines()
	await _in_city(city)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, "skate park: " + label)


func _layout() -> void:
	var pits: Array = SkatePark.pits()
	_check(pits.size() == 2, "a pool and a snake run are cut")
	for pit: Dictionary in pits:
		var rim: PackedVector2Array = pit.rim
		var inside := true
		for p in rim:
			if absf(p.x) > SkatePark.HALF_W - 1.2 or p.y < -SkatePark.HALF_L + 1.2 or p.y > -1.2:
				inside = false
		_check(inside, "the %s's rim stays on the high deck with room round it" % pit.name)
		_check(SkatePark._area(rim) > 0.0 and rim.size() > 40, "the %s's rim is a closed ring" % pit.name)
	var pool: PackedVector2Array = pits[0].rim
	var snake: PackedVector2Array = pits[1].rim
	var gap := INF
	for p in pool:
		gap = minf(gap, SkatePark._dist_to_poly(p, snake))
	_check(gap > 1.5, "the pool and the snake run are %.1f m apart" % gap)
	_check(absf(SkatePark.surface_y(SkatePark.POOL_C) - SkatePark.FLOOR) < 0.01, "the pool's floor is at the cut")
	_check(absf(SkatePark.surface_y(Vector2(-14.0, -21.0)) - SkatePark.H_HI) < 0.01, "the high deck is at its height")
	_check(absf(SkatePark.surface_y(Vector2(-1.0, 20.0)) - SkatePark.H_LO) < 0.01, "the terrace is at its height")
	var mid := SkatePark.surface_y(Vector2(4.0, SkatePark.STEP_RUN * 0.5))
	_check(mid < SkatePark.H_HI and mid > SkatePark.H_LO, "the stair set steps down between them")
	var lip := SkatePark.mini_y(SkatePark.MINI_ZC + SkatePark.MINI_FLAT * 0.5 + SkatePark.mini_reach())
	_check(absf(lip - (SkatePark.H_LO + SkatePark.MINI_H)) < 0.02, "the mini ramp's lip is at its height")
	# The terrace's pieces: inside it, clear of each other and of the mini ramp.
	var reach := SkatePark.MINI_FLAT * 0.5 + SkatePark.mini_reach() + SkatePark.MINI_DECK
	var rects := {
		"mini": Rect2(SkatePark.MINI_X0, SkatePark.MINI_ZC - reach, SkatePark.MINI_X1 - SkatePark.MINI_X0, reach * 2.0),
		"manual": _rect(SkatePark.MANUAL), "ledge": _rect(SkatePark.LEDGE),
		"funbox": _rect(SkatePark.FUNBOX).grow_individual(0.0, SkatePark.FUNBOX_KICK, 0.0, SkatePark.FUNBOX_KICK),
		"bar": Rect2(SkatePark.FLATBAR[0] - 0.1, SkatePark.FLATBAR[1], 0.2, SkatePark.FLATBAR[2] - SkatePark.FLATBAR[1]),
	}
	var terrace := Rect2(-SkatePark.HALF_W, SkatePark.STEP_RUN, SkatePark.HALF_W * 2.0, SkatePark.HALF_L - SkatePark.STEP_RUN)
	var names := rects.keys()
	var clear := true
	for i in names.size():
		var r: Rect2 = rects[names[i]]
		if not terrace.grow(0.01).encloses(r):
			clear = false
		for j in range(i + 1, names.size()):
			if r.grow(0.8).intersects(rects[names[j]]):
				clear = false
	_check(clear, "the street pieces and the mini ramp stand on the terrace, clear of each other")
	# The geometry, built on its own: tens of thousands of triangles near, a few thousand far.
	var g := SkatePark.Geo.new(true)
	SkatePark._build_geo(g, PackedVector2Array(), true)
	var gf := SkatePark.Geo.new(false)
	SkatePark._build_geo(gf, PackedVector2Array(), false)
	var near := g.verts.size() / 3
	var far := gf.verts.size() / 3
	_check(near > 6000 and near < 30000 and far < near / 2, "the park is %d triangles near, %d far" % [near, far])
	_check(SkateParkLife.board_mesh().get_surface_count() == 1, "the board is built")


func _rect(b: Array) -> Rect2:
	return Rect2(float(b[0]), float(b[2]), float(b[1]) - float(b[0]), float(b[3]) - float(b[2]))


func _lines() -> void:
	var tables := {}
	for name: String in SkateParkLife.lines().keys():
		var tb: Dictionary = SkateParkLife.sample(name)
		tables[name] = tb
		var pos: PackedVector3Array = tb.pos
		var pose: PackedByteArray = tb.pose
		var n := pos.size()
		var worst_step := 0.0
		var below := 0.0
		var off := 0.0
		var airs := 0
		var out := false
		for i in n:
			var a := pos[i]
			var b := pos[(i + 1) % n]
			worst_step = maxf(worst_step, a.distance_to(b))
			var s := SkatePark.surface_y(Vector2(a.x, a.z))
			below = maxf(below, s - a.y)
			if pose[i] == SkateParkLife.P_RIDE or pose[i] == SkateParkLife.P_CROUCH:
				off = maxf(off, absf(a.y - s))
			if pose[i] == SkateParkLife.P_AIR:
				airs += 1
			if absf(a.x) > SkatePark.HALF_W - 0.3 or absf(a.z) > SkatePark.HALF_L - 0.3:
				out = true
		_check(n > 90, "the %s line is %.1f s" % [name, tb.length])
		_check(worst_step < 0.4, "the %s line never jumps (%.2f m a sample at most)" % [name, worst_step])
		_check(below < 0.02, "the %s line never goes under the concrete (%.3f m)" % [name, below])
		_check(off < 0.03, "the %s line rides on the surface where it is not in the air (%.3f m off)" % [name, off])
		_check(airs > 5, "the %s line leaves the ground (%d samples in the air)" % [name, airs])
		_check(not out, "the %s line stays inside the pad" % name)
	# Kickflips on the street and down the stairs: the board rolls a whole turn.
	for name: String in ["street", "stairs"]:
		var flips: PackedFloat32Array = (tables[name] as Dictionary).flip
		var top := 0.0
		for f in flips:
			top = maxf(top, f)
		_check(top > 0.99, "the %s line has a kickflip" % name)
	# The stair set: the flip leaves the high deck and lands on the terrace.
	var st: Dictionary = tables["stairs"]
	var start_y := -1.0
	var end_y := -1.0
	var sf: PackedFloat32Array = st.flip
	for i in sf.size():
		if sf[i] >= 0.0 and (i == 0 or sf[i - 1] < 0.0) and start_y < 0.0:
			start_y = (st.pos as PackedVector3Array)[maxi(i - 2, 0)].y
		if sf[i] >= 0.0 and i + 1 < sf.size() and sf[i + 1] < 0.0 and end_y < 0.0:
			var k := i + 1
			while k < sf.size() and (st.pose as PackedByteArray)[k] == SkateParkLife.P_AIR:
				k += 1
			end_y = (st.pos as PackedVector3Array)[mini(k, sf.size() - 1)].y
	_check(absf(start_y - SkatePark.H_HI) < 0.15 and absf(end_y - SkatePark.H_LO) < 0.15, "the kickflip goes down the stair set (from %.2f to %.2f)" % [start_y, end_y])
	# A rider's frame: the board along the way it goes, the surface's up.
	var r := SkateParkLife.at("pool", 3.0)
	var xf: Transform3D = r[0]
	_check(absf(xf.basis.x.dot(xf.basis.y)) < 0.01 and xf.basis.y.y > 0.2, "a rider's frame is upright on the surface")


func _in_city(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	if plan == null or plan.macro == null:
		return
	var anchor := Vector2.ZERO
	for lm in Landmarks.all():
		if lm.id == "venice_boardwalk":
			anchor = lm.anchor
	# The switch: SKATE_PARK=0 lays the boardwalk's old box park.
	var scratch := Node3D.new()
	var scratch_body := StaticBody3D.new()
	scratch.add_child(scratch_body)
	var was := SkatePark.enabled
	SkatePark.enabled = false
	LandmarkVeniceBoardwalk._skate_park(anchor, scratch, scratch_body, plan)
	var old_ok := scratch.get_node_or_null("SkatePark") == null and scratch.get_child_count() > 10
	SkatePark.enabled = was
	scratch.free()
	_check(old_ok, "SKATE_PARK=0 builds the old box park")
	var base := SkatePark.origin(anchor, plan)
	var palms := SkatePark.palm_spots(anchor, plan)
	var clear := true
	var why := ""
	for p in palms:
		for pit: Dictionary in SkatePark.pits():
			if Geometry2D.is_point_in_polygon(p, pit.rim) or SkatePark._dist_to_poly(p, pit.rim) < 1.6:
				clear = false
				why += " %s by the %s" % [p, pit.name]
		for name: String in SkateParkLife.lines().keys():
			for q: Vector3 in (SkateParkLife.sample(name).pos as PackedVector3Array):
				if Vector2(q.x, q.z).distance_to(p) < 1.3:
					clear = false
					why += " %s by the %s line" % [p, name]
					break
	_check(clear, "the boardwalk's palms kept on the pad (%d) stand clear of the pits and the lines%s" % [palms.size(), why])
	var skipped := 0
	var B := LandmarkVeniceBoardwalk
	for row in B.PALM_ROW_X.size():
		for i in int(B.LENGTH / B.PALM_SPACING):
			var z := -B.LENGTH * 0.5 + (float(i) + 0.5 + float(row) * 0.5) * B.PALM_SPACING
			if SkatePark.skips_palm(anchor, plan, B._at(anchor, plan, float(B.PALM_ROW_X[row]), z, 0.0)):
				skipped += 1
	_check(skipped <= 6, "the boardwalk leaves out only the palms in the park's way (%d)" % skipped)
	var player := _tree.get_first_node_in_group("player") as CharacterBody3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	player.global_position = ws.to_local(base + Vector3(30.0, 2.0, 0.0))
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	await _tree.physics_frame
	await _tree.physics_frame
	var root: Node3D = null
	for c in city.chunks.values():
		var ch := c as Node
		if ch != null and is_instance_valid(ch) and ch.get("built_landmarks") != null and (ch.built_landmarks as Array).has("venice_boardwalk"):
			root = ch.get_node_or_null("SkatePark") as Node3D
			if root:
				break
	_check(root != null, "the boardwalk's chunk builds the skate park")
	if root == null:
		player.global_position = ws.to_local(home)
		return
	_check(root.get_node_or_null("Concrete") is MeshInstance3D, "the park's concrete is drawn")
	# Solid: rays from above land on the pool's floor, the high deck and the terrace.
	var space := player.get_world_3d().direct_space_state
	var ray := func(at: Vector2) -> float:
		var w := base + Vector3(at.x, 30.0, at.y)
		var q := PhysicsRayQueryParameters3D.create(ws.to_local(w), ws.to_local(w - Vector3(0.0, 40.0, 0.0)), 1)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return -100.0 if hit.is_empty() else (ws.to_world(hit.position) as Vector3).y - base.y
	var floor_y: float = ray.call(SkatePark.POOL_C)
	var deck_y: float = ray.call(Vector2(-13.5, -20.5))
	var terr_y: float = ray.call(Vector2(-1.0, 20.0))
	_check(absf(floor_y - SkatePark.FLOOR) < 0.05, "the pool's floor is solid (%.2f)" % floor_y)
	_check(absf(deck_y - SkatePark.H_HI) < 0.05, "the high deck is solid (%.2f)" % deck_y)
	_check(absf(terr_y - SkatePark.H_LO) < 0.05, "the terrace is solid (%.2f)" % terr_y)
	var life := root.get_node_or_null("SkateParkLife") as SkateParkLife
	_check(life != null, "the park has its life")
	if life == null:
		player.global_position = ws.to_local(home)
		return
	_check(life.skaters().size() == SkateParkLife.RIDERS.size() and life.spectators().size() == SkateParkLife.SPECTATORS.size(),
		"%d skaters and %d spectators" % [life.skaters().size(), life.spectators().size()])
	# The riders follow the clock.
	var hold_was := SkateParkLife.hold
	SkateParkLife.hold = true
	life.set_clock(7.0)
	var sk: SkateParkLife.Skater = life.skaters()[0]
	var want: Transform3D = SkateParkLife.at(sk.line, 7.0 * sk.pace + sk.phase)[0]
	_check(sk.transform.origin.distance_to(want.origin) < 0.01, "a skater is where its line says at the clock")
	var p0 := sk.global_position
	life.set_clock(9.0)
	_check(sk.global_position.distance_to(p0) > 3.0, "and rides on with it (%.1f m in 2 s)" % sk.global_position.distance_to(p0))
	# A spectator hit becomes a live person where they stood; a knocked skater leaves the line (and
	# the person they become is knocked straight into a ragdoll).
	var holder := root.get_parent()
	var left := life.figures_left()
	var spec: Node = life.spectators()[3]
	var ped: Node = spec.wake(Vector3.ZERO)
	_check(ped != null and ped.get_parent() == holder and ped is SkaterPerson, "a woken spectator is a live person in the chunk")
	sk.knock(Vector3(3.0, 1.0, 0.0))
	await _tree.process_frame
	_check(life.figures_left() == left - 2 and not is_instance_valid(sk), "a knocked skater leaves the line (%d -> %d figures)" % [left, life.figures_left()])
	# Gunfire next to the park wakes the nearest of the rest, a few a tick.
	left = life.figures_left()
	Pedestrian.alarm(_tree, root.global_position + Vector3(0.0, 3.0, -10.0), 40.0, 0, true, "")
	for i in 40:
		await _tree.physics_frame
	var woke := left - life.figures_left()
	_check(woke >= 3 and woke <= SkateParkLife.WAKE_PER_ALARM, "gunfire by the park wakes %d people" % woke)
	SkateParkLife.hold = hold_was
	for n in holder.get_children():
		if n is SkaterPerson:
			n.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _tree.physics_frame

