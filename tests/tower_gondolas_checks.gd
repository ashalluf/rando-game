extends RefCounted
## Window-washing gondolas (TowerGondolas, GondolaRig), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## The landmark sites are pure and stand on real faces (the edge on a tier's outline, the roof
## behind it, nothing standing on the davit spots, the column outside the face clear of every
## other tier down to the drop's foot); the descent is worked out from the clock and stays on the
## face; a forced rig builds its cradle on the props layer (mask 0, metal to the guns), swings
## when shot and settles again, never through the glass, and frees everything it built; a glass
## tower's hanging BMU hands its cradle over; GONDOLAS off builds nothing.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var TG = load("res://scripts/world/tower_gondolas.gd")
	var LD = load("res://scripts/world/landmark_downtown.gd")
	_sites(TG, LD)
	_motion(TG, LD)
	_live(TG, LD, city)
	_building(TG)
	var sh := load("res://shaders/gondola_streaks.gdshader") as Shader
	_t._check(sh != null and sh.get_shader_uniform_list().size() >= 5, "the gondola water shader loads with its uniforms")


func _sites(TG, LD) -> void:
	var towers := 0
	var hung := 0
	var bad := ""
	for id: String in LD.TOWERS:
		var s: Dictionary = TG.landmark_sites(id, 1337)
		TG._site_cache.clear()
		var s2: Dictionary = TG.landmark_sites(id, 1337)
		if str(s) != str(s2):
			bad += "%s impure; " % id
		if s.hung.is_empty():
			continue
		towers += 1
		var t: Dictionary = LD.tower(id)
		var hulls: Array = TG._hull_boxes(t.hulls)
		for site: Dictionary in s.hung:
			hung += 1
			var n: Vector3 = site.n
			var m: Vector3 = site.m
			if absf(n.length() - 1.0) > 0.001 or absf(n.y) > 0.001:
				bad += "%s normal; " % id
			if float(site.top) - float(site.bottom) < TG.MIN_DROP:
				bad += "%s short drop; " % id
			# The edge is on some tier's outline and the roof is behind it.
			var on_edge := false
			for tier: Array in t.tiers:
				var outline: PackedVector2Array = tier[0]
				if absf(float(tier[2]) + TowerMesh.PARAPET_HEIGHT - m.y) < 0.05 \
						and Geometry2D.is_point_in_polygon(Vector2(m.x, m.z) - Vector2(n.x, n.z) * 0.5, outline) \
						and not Geometry2D.is_point_in_polygon(Vector2(m.x, m.z) + Vector2(n.x, n.z) * 0.5, outline):
					on_edge = true
			if not on_edge:
				bad += "%s edge off its tier; " % id
			# The cradle's column outside the face, every lane, clear of every hull down to its foot.
			for lane: float in site.lanes:
				for k in 9:
					var y: float = lerpf(float(site.bottom) + 0.5, float(site.top) + 1.8, float(k) / 8.0)
					var p: Vector3 = m + (site.t as Vector3) * lane + n * TowerGondolas.GAP
					for e: float in [-TowerGondolas.CRADLE_LEN * 0.5, TowerGondolas.CRADLE_LEN * 0.5]:
						var q := p + (site.t as Vector3) * e
						if TG._blocked(hulls, Vector2(q.x, q.z), y - 0.1, y + 0.1):
							bad += "%s lane %.1f inside a hull at %.0f m; " % [id, lane, y]
							break
	_t._check(bad == "", "gondola sites are pure and hang on real faces, clear of the tower (%s)" % bad)
	_t._check(towers >= 3 and hung >= 4, "the downtown towers carry window-washing gondolas (%d towers, %d cradles)" % [towers, hung])


func _motion(TG, LD) -> void:
	var site: Dictionary = {}
	for id: String in LD.TOWERS:
		var s: Dictionary = TG.landmark_sites(id, 1337)
		if not s.hung.is_empty():
			site = s.hung[0]
			break
	if site.is_empty():
		_t._check(false, "a gondola site to move")
		return
	var bad := ""
	var states := {}
	var prev_y := INF
	var prev_lane := INF
	var rose := 0
	for i in 2400:
		var t := float(i) * 3.0
		var p: Dictionary = TG.pose_at(site, t)
		if str(p) != str(TG.pose_at(site, t)):
			bad += "impure; "
			break
		states[int(p.moving)] = true
		if float(p.y) < float(site.bottom) - 0.01 or float(p.y) > float(site.top) + 0.01:
			bad += "y %.1f off the face; " % p.y
			break
		if not (site.lanes as Array).has(p.lane):
			bad += "lane; "
			break
		# Going down a drop it only ever goes down (or holds), winching up only between drops.
		if prev_y != INF and float(p.y) > prev_y + 0.01 and int(p.moving) != 2 and p.lane == prev_lane:
			rose += 1
		prev_y = p.y
		prev_lane = p.lane
	_t._check(bad == "" and rose == 0 and states.size() == 3,
		"a gondola washes its drop floor by floor, then winches up and moves lanes (%s rose=%d states=%s)" % [bad, rose, str(states.keys())])


func _live(TG, LD, city: Node3D) -> void:
	var id := ""
	for k: String in LD.TOWERS:
		if not (TG.landmark_sites(k, TG._world_seed(city)).hung as Array).is_empty():
			id = k
			break
	var holder := Node3D.new()
	holder.name = "GondolaCheck"
	city.add_child(holder)
	var statics := StaticBody3D.new()
	holder.add_child(statics)
	var at := Vector3(0.0, -4000.0, 0.0)
	TG.landmark(holder, at, id)
	var rigs: Array = holder.find_children("GondolaRig", "Node3D", true, false)
	_t._check(not rigs.is_empty(), "a tower's gondola rigs stand under it (%s: %d)" % [id, rigs.size()])
	if rigs.is_empty():
		holder.free()
		return
	var rig = rigs[0]
	var live0: int = TG.live
	rig.force = true
	rig._manage()
	var body = rig._body
	var ok: bool = rig.built and body != null and body.collision_layer == 4 and body.collision_mask == 0 \
		and body.is_in_group("rail_vehicle") and body.has_method("take_hit") and TG.live == live0 + 1
	_t._check(ok, "a near gondola builds its cradle on the props layer, metal to the guns")
	_t._check(rig.has_workers and rig._workers.size() == 2, "two workers stand in the cradle (%d)" % rig._workers.size())
	rig._update(1.0 / 60.0)
	var rest: Transform3D = body.transform
	body.take_hit(0, 10.0, -(rig.site.n as Vector3))
	body.take_hit(0, 120.0, (rig.site.n as Vector3) + (rig.site.t as Vector3))
	var max_out := 0.0
	var min_out := INF
	var through := false
	for i in 600:
		rig._update(1.0 / 60.0)
		max_out = maxf(max_out, rig._xo)
		min_out = minf(min_out, rig._xo)
		if rig._xo < -0.001:
			through = true
	var finite: bool = (body.transform as Transform3D).origin.is_finite()
	_t._check(rig.hits == 2 and max_out > 0.3 and not through and finite and rig._brace_w > 0.5,
		"a shot gondola swings out (%.2f m), never through the glass, and the workers hang on" % max_out)
	for i in 6000:
		rig._update(1.0 / 20.0)
	_t._check(absf(rig._yaw) < 0.02 and absf(rig._roll) < 0.02, "the swing settles (yaw %.3f roll %.3f)" % [rig._yaw, rig._roll])
	var rope: MeshInstance3D = rig._ropes[0]
	_t._check(rope.transform.basis.y.length() > 0.5 and rope.transform.origin.is_finite(), "the cradle hangs on its ropes")
	rig.force = false
	rig._drop()
	_t._check(not rig.built and TG.live == live0 and body.is_queued_for_deletion(), "a far gondola frees what it built")
	holder.free()
	# Off: nothing.
	TG.enabled = false
	var h2 := Node3D.new()
	city.add_child(h2)
	TG.landmark(h2, at, id)
	_t._check(h2.get_child_count() == 0, "GONDOLAS=0 builds no gondola")
	TG.enabled = true
	h2.free()


func _building(TG) -> void:
	var R = load("res://scripts/world/rooftops.gd")
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var found = null
	for i in 400:
		var b = scene.instantiate()
		b.seed = 9001 + i * 7919
		b.lot_size = Vector2(40.0, 40.0)
		b.min_height = 90.0
		b.max_height = 140.0
		b.plan_only()
		b.roof_plan()
		var p: Dictionary = R.plan(b)
		var hang := false
		for f: Dictionary in p.get("feats", []):
			if f.kind == "bmu" and f.hang:
				hang = true
		b.free()
		if hang:
			found = 9001 + i * 7919
			break
	if found == null:
		_t._check(false, "a glass tower with a hanging window-washing machine")
		return
	var b = scene.instantiate()
	b.seed = found
	b.lot_size = Vector2(40.0, 40.0)
	b.min_height = 90.0
	b.max_height = 140.0
	_t.get_tree().root.add_child(b)
	var rigs: Array = b.find_children("GondolaRig", "Node3D", true, false)
	var tris_on: int = b.get_meta("rooftops_tris", 0)
	var ok := rigs.size() == 1
	if ok:
		var s: Dictionary = rigs[0].site
		ok = int(s.support) == 1 and float(s.top) > float(s.bottom) + 3.0 and (s.heads as Array).size() == 2 \
			and (s.heads[0] as Vector3).distance_to(s.heads[1]) > 2.0
	_t._check(ok, "a glass tower's hanging BMU carries a live cradle under its jib (seed %d)" % found)
	b.free()
	# One cradle per tower: with the gondolas on, Rooftops draws no static cradle on that machine
	# (its mesh is lighter by the cradle and its ropes) and the live one is the only one.
	TG.enabled = false
	var b2 = scene.instantiate()
	b2.seed = found
	b2.lot_size = Vector2(40.0, 40.0)
	b2.min_height = 90.0
	b2.max_height = 140.0
	_t.get_tree().root.add_child(b2)
	var tris_off: int = b2.get_meta("rooftops_tris", 0)
	var rigs_off: int = b2.find_children("GondolaRig", "Node3D", true, false).size()
	b2.free()
	TG.enabled = true
	_t._check(ok and tris_on < tris_off and rigs_off == 0,
		"a BMU tower carries one cradle: the live one, never Rooftops' static one too (%d < %d tris)" % [tris_on, tris_off])
	# The landmark towers: Rooftops gives them a helipad and no machine, so the davit cradles and the
	# parked BMUs are the only ones there, never two on one face.
	var LD = load("res://scripts/world/landmark_downtown.gd")
	var bad := ""
	for id: String in LD.TOWERS:
		var s: Dictionary = TG.landmark_sites(id, 1337)
		var normals: Array = []
		for site: Dictionary in s.hung:
			normals.append(site.n)
		for p: Dictionary in s.parked:
			normals.append(p.n)
		for i in normals.size():
			for j in range(i + 1, normals.size()):
				if (normals[i] as Vector3).dot(normals[j]) > 0.99:
					bad += id + " "
	_t._check(bad == "", "no landmark face carries two cradles or machines (%s)" % bad)
