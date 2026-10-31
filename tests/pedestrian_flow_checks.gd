extends RefCounted
## The crowd's flow (CrowdFlow, scripts/npc/crowd_flow.gd) for tests/smoke_test.gd: the pure
## reciprocal step (two walkers meeting head on pass right shoulder to right shoulder and never
## touch, a walker steps round somebody standing, a crowded pavement is slower), the follower's
## slot and the pavement band, the car-at-the-kerb rule; then on the spawn block: the chunks'
## walkers are grouped, a follower keeps beside its leader, two live walkers on one line pass each
## other instead of walking through, two walkers planning the same crosswalk take different places
## at the kerb and step off on their own beat, and a walker comes out of a shop door. Loaded at
## run time, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_pure()
	if not CrowdFlow.enabled:
		_check(true, "the crowd flow is off (CROWD_FLOW=0): only the pure checks ran")
		return
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the crowd flow checks")
	if chunk == null:
		return
	_groups_spawned(city)
	await _follower(city, chunk)
	await _passing(city, chunk)
	await _kerb(city, chunk)
	await _doors(city)


# --- Pure -----------------------------------------------------------------------------------------

func _pure() -> void:
	# Head on, both on the same line: they pass, keeping right, and never come within a body.
	var a := Vector2(0.0, 0.0)
	var b := Vector2(0.03, -12.0)
	var ga := Vector2(0.0, -16.0)
	var gb := Vector2(0.0, 4.0)
	var va := Vector2.ZERO
	var vb := Vector2.ZERO
	var closest := INF
	var a_right_at_pass := false
	var dt := 1.0 / 60.0
	for i in 60 * 14:
		var da := (ga - a).normalized() if a.distance_to(ga) > 0.2 else Vector2.ZERO
		var db := (gb - b).normalized() if b.distance_to(gb) > 0.2 else Vector2.ZERO
		var ra := CrowdFlow.step(a, da, 1.3, [[b, vb]]) if da != Vector2.ZERO else Vector3.ZERO
		var rb := CrowdFlow.step(b, db, 1.3, [[a, va]]) if db != Vector2.ZERO else Vector3.ZERO
		va = Vector2(ra.x, ra.y) * ra.z
		vb = Vector2(rb.x, rb.y) * rb.z
		a += va * dt
		b += vb * dt
		var d := a.distance_to(b)
		if d < closest:
			closest = d
			a_right_at_pass = a.x > b.x
	_check(closest > 2.0 * CrowdFlow.RADIUS and a_right_at_pass and a.distance_to(ga) < 1.0 and b.distance_to(gb) < 1.0,
		"two walkers meeting head on pass keeping right and never touch (closest %.2f m, A to its right %s, both there %s)" % [closest, a_right_at_pass, a.distance_to(ga) < 1.0 and b.distance_to(gb) < 1.0])
	# Somebody standing dead ahead: stepped round, and the walk goes on.
	a = Vector2.ZERO
	var standing := Vector2(0.0, -6.0)
	closest = INF
	for i in 60 * 12:
		var da := (ga - a).normalized() if a.distance_to(ga) > 0.2 else Vector2.ZERO
		if da == Vector2.ZERO:
			break
		var ra := CrowdFlow.step(a, da, 1.3, [[standing, Vector2.ZERO]])
		a += Vector2(ra.x, ra.y) * ra.z * dt
		closest = minf(closest, a.distance_to(standing))
	_check(closest > 2.0 * CrowdFlow.RADIUS and a.distance_to(ga) < 1.0,
		"a walker steps round somebody standing in the way (closest %.2f m, end %.1f m from the goal)" % [closest, a.distance_to(ga)])
	# A crowded pavement (people beside, not in the way): slower than an empty one.
	var crowd: Array = []
	for k in 6:
		crowd.append([Vector2(1.4 if k % 2 == 0 else -1.4, -0.4 * float(k)), Vector2(0.0, -1.2)])
	var free := CrowdFlow.step(Vector2.ZERO, Vector2(0.0, -1.0), 1.4, [])
	var busy := CrowdFlow.step(Vector2.ZERO, Vector2(0.0, -1.0), 1.4, crowd)
	_check(is_equal_approx(free.z, 1.4) and busy.z < 1.4 * 0.85 and busy.z >= 1.4 * CrowdFlow.DENSITY_MIN - 0.01,
		"a crowded pavement slows the walk (%.2f m/s alone, %.2f among six)" % [free.z, busy.z])
	# Falling in behind somebody slower in a pavement too full to pass: their pace, not a collision.
	var queue: Array = [[Vector2(0.0, -1.3), Vector2(0.0, -0.7)], [Vector2(0.75, -1.1), Vector2(0.0, -0.7)], [Vector2(-0.75, -1.1), Vector2(0.0, -0.7)]]
	var behind := CrowdFlow.step(Vector2.ZERO, Vector2(0.0, -1.0), 1.4, queue)
	_check(behind.z < 1.1, "boxed in behind slower walkers, a walker slows to them (%.2f m/s)" % behind.z)
	# Slots: either side of the leader, and kept on the pavement band.
	var s0 := CrowdFlow.slot_point(Vector2(10.0, 10.0), 0.0, 0, 1.0)
	var s1 := CrowdFlow.slot_point(Vector2(10.0, 10.0), 0.0, 1, 1.0)
	_check(s0.x > 10.5 and s1.x < 9.5 and s1.y > s0.y,
		"a pair walks abreast and a third on the other side a little behind (%s, %s)" % [s0, s1])
	var ring := Rect2(0.0, 0.0, 100.0, 80.0)
	var out := CrowdFlow.band_clamp(Vector2(30.0, -0.5), ring, 4.0)
	var inside := CrowdFlow.band_clamp(Vector2(30.0, 6.0), ring, 4.0)
	_check(out.y >= 0.5 and inside.y <= 3.6 and is_equal_approx(out.x, 30.0),
		"a slot is kept on the pavement band, never in the road or the block (%s, %s)" % [out, inside])
	# The kerb: a car coming on the crossed road waits them; one going away, stopped or on the
	# other road does not.
	var along := Vector2(1.0, 0.0)
	var across := Vector2(0.0, 1.0)
	_check(CrowdFlow.car_blocks(Vector2(-20.0, 1.5), Vector2(9.0, 0.0), along, across, 5.0, 32.0)
		and not CrowdFlow.car_blocks(Vector2(-20.0, 1.5), Vector2(-9.0, 0.0), along, across, 5.0, 32.0)
		and not CrowdFlow.car_blocks(Vector2(-8.0, 1.5), Vector2.ZERO, along, across, 5.0, 32.0)
		and not CrowdFlow.car_blocks(Vector2(-20.0, 14.0), Vector2(9.0, 0.0), along, across, 5.0, 32.0)
		and not CrowdFlow.car_blocks(Vector2(-60.0, 1.5), Vector2(14.0, 0.0), along, across, 5.0, 32.0),
		"at the kerb a car coming waits a walker; one going away, stopped, far or on the other road does not")
	# The switch.
	CrowdFlow.enabled = false
	var off := CrowdFlow.avoid(null, Vector2(0.0, -3.0), 1.2, false)
	CrowdFlow.enabled = true
	_check(off == Vector3(0.0, -3.0, 1.2), "CROWD_FLOW=0 leaves the heading and pace as they were")


# --- The city ---------------------------------------------------------------------------------

func _groups_spawned(city: Node3D) -> void:
	var groupable := 0
	var followers := 0
	var trios := 0
	for c: Node in city.chunks.values():
		if int(c.get("level")) != CityChunk.Level.FULL:
			continue
		for n in c.get_children():
			var p := n as Pedestrian
			if p == null or not CrowdFlow._groupable(p):
				continue
			groupable += 1
			if p.flow.get("leader") != null:
				followers += 1
			if int(p.flow.get("followers", 0)) >= 2:
				trios += 1
	var share := float(followers) / maxf(float(groupable), 1.0)
	_check(groupable < 10 or (followers > 0 and share < 0.5),
		"the chunks' walkers come in pairs and threes as well as alone (%d followers of %d, %d threes)" % [followers, groupable, trios])


func _walker(chunk: Node3D, rect: Rect2, at: Vector2, seed_value: int) -> Pedestrian:
	var p := Pedestrian.new()
	var plan: CityPlan = chunk.get("plan")
	p.setup(rect, plan.sidewalk_width if plan else 4.0, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_range = 0.0
	p.set_meta("no_trim", true)
	p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
	chunk.add_child(p)
	return p


## The north pavement of the spawn block nearest the camera, and a run along it.
func _strip(city: Node3D, chunk: Node3D) -> Array:
	var rect: Rect2 = city.plan.block(0, 0).rect
	var cam := _tree.root.get_viewport().get_camera_3d()
	var cw := WorldState.to_world(cam.global_position) if cam else Vector3(rect.get_center().x, 0.0, rect.position.y)
	var x0 := clampf(cw.x, rect.position.x + 12.0, rect.end.x - 26.0)
	return [rect, Vector2(x0, rect.position.y + 2.0)]


func _follower(city: Node3D, chunk: Node3D) -> void:
	var s := _strip(city, chunk)
	var rect: Rect2 = s[0]
	var at: Vector2 = s[1]
	var l := _walker(chunk, rect, at, 90101)
	var f := _walker(chunk, rect, at + Vector2(-2.0, 0.6), 90102)
	await _ticks(2)
	CrowdFlow.join(f, l, false)
	l._go_to(Vector2(at.x + 14.0, at.y))
	var sum := 0.0
	var n := 0
	var start := Vector2(l.position.x, l.position.z)
	for i in 60 * 9:
		await _tree.physics_frame
		if i > 150:
			sum += Vector2(f.position.x, f.position.z).distance_to(Vector2(l.position.x, l.position.z))
			n += 1
	var moved := Vector2(l.position.x, l.position.z).distance_to(start)
	var mean := sum / maxf(float(n), 1.0)
	_check(f.flow.get("leader") != null and mean < 1.6 and moved > 6.0,
		"a follower walks beside its leader and stands with it when it stops (mean %.2f m apart, leader went %.1f m, grouped %s)" % [mean, moved, f.flow.get("leader") != null])
	l.queue_free()
	await _ticks(2)
	_check(f.flow.get("leader") == null, "a follower whose leader is gone walks on alone")
	f.queue_free()


func _passing(city: Node3D, chunk: Node3D) -> void:
	var s := _strip(city, chunk)
	var rect: Rect2 = s[0]
	var at: Vector2 = s[1]
	var a := _walker(chunk, rect, at, 90201)
	var b := _walker(chunk, rect, at + Vector2(13.0, 0.0), 90202)
	await _ticks(30) # the LOD pass: near enough to step through move_and_slide
	a._go_to(at + Vector2(16.0, 0.0))
	b._go_to(at + Vector2(-3.0, 0.0))
	var closest := INF
	var passed := false
	for i in 60 * 14:
		await _tree.physics_frame
		var pa := Vector2(a.position.x, a.position.z)
		var pb := Vector2(b.position.x, b.position.z)
		closest = minf(closest, pa.distance_to(pb))
		if pa.x > pb.x + 1.0:
			passed = true
			break
	_check(passed and closest > 0.45,
		"two walkers on one line step round each other instead of through (closest %.2f m, passed %s, kinematic %s)" % [closest, passed, a._kinematic])
	a.queue_free()
	b.queue_free()


func _kerb(city: Node3D, chunk: Node3D) -> void:
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var corner := rect.position + Vector2(2.5, 5.0)
	var a := _walker(chunk, rect, corner, 90301)
	var b := _walker(chunk, rect, corner + Vector2(0.8, 1.0), 90302)
	await _ticks(2)
	TrafficSignals.force(plan, 0, 0, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.5)
	var pa := a.plan_crossing(CityPlan.AXIS_Z)
	var pb := b.plan_crossing(CityPlan.AXIS_Z)
	var ka := int(a.flow.get("kerb_slot", -1))
	var kb := int(b.flow.get("kerb_slot", -1))
	_check(pa and pb and a._cross_key == b._cross_key and ka != kb and a._cross_from.distance_to(b._cross_from) > 0.5,
		"two walkers at one crosswalk take different places at the kerb (slots %d and %d, %.2f m apart)" % [ka, kb, a._cross_from.distance_to(b._cross_from)])
	# At the kerb, the light says go: each steps off on their own beat, not on the same tick.
	a._cross = Pedestrian.Cross.WAIT
	a.flow.erase("go_at")
	var first := CrowdFlow.may_go(a)
	_check(not first and int(a.flow.get("go_at", 0)) > Pedestrian._life_now_ms(),
		"when the walking figure comes up a walker steps off a beat later, not on the same tick")
	TrafficSignals.force(plan, 0, 0, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.5)
	a.queue_free()
	b.queue_free()
	await _ticks(2)


func _doors(city: Node3D) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var plan: CityPlan = city.plan
	if player == null:
		return
	var pw := WorldState.to_world(player.global_position)
	var here := Vector2(pw.x, pw.z)
	var ci := plan.chunk_index_at(here)
	var near := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c: Variant = city.chunks.get(ci + Vector2i(dx, dz))
			if c is Node and int((c as Node).get("level")) == CityChunk.Level.FULL:
				for d: Dictionary in StreetErrands._doors(c):
					var dd := (d.p as Vector2).distance_to(here)
					if dd >= CrowdFlow.DOOR_RANGE.x and dd <= CrowdFlow.DOOR_RANGE.y:
						near += 1
	var any: Pedestrian = null
	for n in _tree.get_nodes_in_group("pedestrian"):
		if n is Pedestrian and (n as Pedestrian)._life_ok:
			any = n
			break
	if near == 0 or any == null or not StreetErrands.enabled:
		_check(true, "no shop door near the spawn (%d) to come out of: nothing to check" % near)
		return
	var traffic: Node = city.get_node_or_null("Traffic")
	var staged: bool = traffic.get("staged") if traffic else false
	if traffic:
		traffic.set("staged", false)
	var before := int(CrowdFlow.stats.doors_out)
	var came := false
	for k in 4:
		CrowdFlow._next_door_ms = 1
		CrowdFlow.door_tick(any)
		if int(CrowdFlow.stats.doors_out) > before:
			came = true
			break
	if traffic:
		traffic.set("staged", staged)
	var shown := false
	var w: Pedestrian = CrowdFlow.last_out.get_ref() if CrowdFlow.last_out else null
	if came and w != null:
		w.set_meta("no_trim", true)
		var door_at := Vector2(w.position.x, w.position.z)
		for i in 60 * 6:
			await _tree.physics_frame
			if not is_instance_valid(w):
				break
			if w.visible and w.collision_layer != 0:
				shown = Vector2(w.position.x, w.position.z).distance_to(door_at) < 3.0
				break
	_check(came and shown, "somebody comes out of a shop door near the player (%d doors in reach, out %s, shown %s)" % [near, came, shown])


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
