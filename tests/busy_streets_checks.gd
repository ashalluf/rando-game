extends RefCounted
## Busy streets (BusyStreets) for tests/smoke_test.gd. Loaded at run time (not named there), so it
## compiles after the autoloads. Checks: the hour curves (full by day, busy in the evening, thin in
## the small hours); the view cone; the focused spawns (most of them round the camera's block,
## inside near_min..focus_max, none popping in close inside the view, more ahead than behind);
## the rear retire rule (out of view and far only, never while the traffic is staged); the kerbs
## (the extra cars are a pure hash of the spot, a block built with them keeps every car it had
## without them and adds some, inside its extra cap); and the crowd top-up (a near block emptied
## of its walkers gets them back, inside the cap, with no walker put down in plain sight close by).
## Everything it needs is staged here; what it changes it puts back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	var saved_enabled := BusyStreets.enabled
	var saved_hour := StreetVendors.force_hour
	BusyStreets.enabled = true
	_hours()
	_cone()
	var tm: TrafficManager = city.get_node_or_null("Traffic")
	if tm:
		_spawns(tm)
		_retire(tm)
	_kerbs(city)
	StreetVendors.force_hour = 13.0
	await _crowd(t, city)
	StreetVendors.force_hour = saved_hour
	BusyStreets.enabled = saved_enabled
	print("BUSY_STREETS_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _hours() -> void:
	var noon := BusyStreets.hour_factor(12.0)
	var rush := BusyStreets.hour_factor(17.5)
	var eve := BusyStreets.hour_factor(21.5)
	var late := BusyStreets.hour_factor(3.0)
	_check(noon > 0.9 and rush > 0.9, "the streets' traffic is full through the day (noon %.2f, 17:30 %.2f)" % [noon, rush])
	_check(eve > 0.55 and eve < noon, "the evening is still busy (21:30 %.2f)" % eve)
	_check(late <= 0.35 and late > 0.0, "the small hours thin out (03:00 %.2f)" % late)
	var c_noon := BusyStreets.crowd_factor(12.0)
	var c_eve := BusyStreets.crowd_factor(22.0)
	var c_late := BusyStreets.crowd_factor(3.5)
	_check(c_noon == 1.0 and c_eve > 0.6 and c_eve < 1.0 and c_late < 0.3,
		"the crowd by hour: noon %.2f, 22:00 %.2f, 03:30 %.2f" % [c_noon, c_eve, c_late])
	_check(is_equal_approx(BusyStreets.crowd_factor(0.0), BusyStreets.crowd_factor(24.0)), "the crowd's day wraps at midnight")


func _cone() -> void:
	var at := Vector3.ZERO
	var fwd := Vector3(0.0, 0.0, -1.0)
	_check(BusyStreets.in_view(at, fwd, Vector3(5.0, 0.0, -100.0)) and not BusyStreets.in_view(at, fwd, Vector3(0.0, 0.0, 100.0))
			and not BusyStreets.in_view(at, fwd, Vector3(100.0, 0.0, -10.0)), "the view cone is ahead of the camera and only ahead")


## The focused spawns, on the traffic's own geometry round wherever the camera is now.
func _spawns(tm: TrafficManager) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var e := BusyStreets.eye(tm.get_tree(), tm._player)
	var at: Vector3 = e[0]
	var fwd: Vector3 = e[1]
	var was_fill := BusyStreets.fill_now
	BusyStreets.fill_now = false
	var focused := 0
	var in_range := 0
	var popped := 0
	var ahead := 0
	var n := 400
	for i in n:
		var p := BusyStreets.pick_spawn(tm, rng)
		if p == Vector3.INF:
			continue
		focused += 1
		var axis := int(p.x)
		var cross := tm.plan.road_pos(axis, int(p.y))
		var w := Vector3(cross, at.y, p.z) if axis == CityPlan.AXIS_X else Vector3(p.z, at.y, cross)
		var a_cam := at.z if axis == CityPlan.AXIS_X else at.x
		var off := absf(p.z - a_cam)
		if off >= BusyStreets.near_min - 0.01 and off <= BusyStreets.focus_max + 0.01:
			in_range += 1
		if BusyStreets.in_view(at, fwd, w) and Vector2(w.x - at.x, w.z - at.z).length() < BusyStreets.view_pop_min - 1.0:
			popped += 1
		var f_along := fwd.z if axis == CityPlan.AXIS_X else fwd.x
		if absf(f_along) > 0.2 and signf(p.z - a_cam) == signf(f_along):
			ahead += 1
	var share := float(focused) / n
	_check(absf(share - BusyStreets.focus_share) < 0.08, "about %.0f %% of the street spawns go round the camera (%.2f)" % [BusyStreets.focus_share * 100.0, share])
	_check(in_range == focused, "a focused spawn is %d-%d m off the camera along its road (%d of %d)" % [BusyStreets.near_min, BusyStreets.focus_max, in_range, focused])
	_check(popped <= focused / 50, "no focused spawn pops in close inside the view (%d of %d)" % [popped, focused])
	_check(ahead > focused / 3, "focused spawns lean ahead of the camera (%d of %d)" % [ahead, focused])
	# Filling (a fresh load or a teleport): bursts, and the near street may fill in plain sight.
	var staged := tm.staged
	tm.staged = false
	var burst := BusyStreets.spawn_burst(tm, tm.cars.size() * 4 + 40)
	var calm := BusyStreets.spawn_burst(tm, 0)
	tm.staged = staged
	_check(burst == BusyStreets.FILL_BURST and calm == 12, "an empty street fills in bursts (%d), a full one at the old pace (%d)" % [burst, calm])
	BusyStreets.fill_now = was_fill
	BusyStreets.enabled = false
	_check(BusyStreets.pick_spawn(tm, rng) == Vector3.INF and BusyStreets.spawn_burst(tm, 999) == 12, "BUSY_STREETS=0 keeps the old spawn rule")
	BusyStreets.enabled = true
	BusyStreets.fill_now = was_fill


func _retire(tm: TrafficManager) -> void:
	var at := Vector3(100.0, 0.0, 100.0)
	var fwd := Vector3(1.0, 0.0, 0.0)
	var was := tm.staged
	tm.staged = false
	var behind := BusyStreets.retire_far(tm, at + Vector3(-300.0, 0.0, 0.0), at, fwd)
	var ahead_far := BusyStreets.retire_far(tm, at + Vector3(300.0, 0.0, 0.0), at, fwd)
	var behind_near := BusyStreets.retire_far(tm, at + Vector3(-100.0, 0.0, 0.0), at, fwd)
	tm.staged = true
	var staged := BusyStreets.retire_far(tm, at + Vector3(-300.0, 0.0, 0.0), at, fwd)
	tm.staged = was
	_check(behind and not ahead_far and not behind_near and not staged,
		"a car goes back to the pool only far off and out of view, never while the traffic is staged")


## A downtown block built with and without the extra kerb cars.
func _kerbs(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	_check(BusyStreets.park_extra_roll(plan.seed, [Vector3(10.0, 0.4, 20.0), 0.0, 1.0]) == BusyStreets.park_extra_roll(plan.seed, [Vector3(10.0, 0.4, 20.0), 0.0, 1.0]),
		"an extra kerb car is a pure hash of the spot")
	var hits := 0
	for i in 400:
		if BusyStreets.park_extra_roll(plan.seed, [Vector3(float(i) * 8.0, 0.4, 37.0), 0.0, 1.0]):
			hits += 1
	_check(absf(hits / 400.0 - BusyStreets.PARK_EXTRA_ODDS) < 0.06, "the extra kerb cars take about %.0f %% of the empty spots (%d of 400)" % [BusyStreets.PARK_EXTRA_ODDS * 100.0, hits])
	# Room in the props budget for both builds (the city round the check may have spent it).
	var saved_budget := PhysicsBudget.max_active_bodies
	PhysicsBudget.max_active_bodies = PhysicsBudget.active_body_count() + 400
	var more := 0
	var kept := true
	var capped := true
	var tried := 0
	for at: Vector2 in [Vector2(2359.0, 880.0), Vector2(900.0, 400.0), Vector2(1100.0, 700.0), Vector2(600.0, 950.0), Vector2(-400.0, 600.0), Vector2(1300.0, -300.0)]:
		var k := plan.block_index_at(at)
		var b := plan.block(k.x, k.y)
		if int(b.kind) != CityPlan.BlockKind.BUILDINGS or plan.zone_at(at) != MacroMap.Zone.CITY:
			continue
		tried += 1
		BusyStreets.enabled = false
		var bare := _cars_of(city, k)
		BusyStreets.enabled = true
		var full := _cars_of(city, k)
		for c: String in bare:
			kept = kept and full.has(c)
		capped = capped and full.size() - bare.size() <= 30
		more += full.size() - bare.size()
	PhysicsBudget.max_active_bodies = saved_budget
	_check(tried > 0 and kept, "a block with the extra kerb cars keeps every car it parked without them (%d blocks)" % tried)
	_check(capped, "the extra kerb cars stay a handful a block")
	_check(more > 0, "the extra kerb cars park more (%d more on %d blocks)" % [more, tried])


func _cars_of(city: Node3D, k: Vector2i) -> Array:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var out: Array = []
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("%d %.1f %.1f" % [int((car as Vehicle).body_type), p.x, p.z])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	return out


## A near block's walkers cleared, then topped up.
func _crowd(t: Node, city: Node3D) -> void:
	var e := BusyStreets.eye(city.get_tree(), city.get("_player") as Node3D)
	var at: Vector3 = e[0]
	var best: CityChunk = null
	var best_entry: Array = []
	var best_d := INF
	for k in city.chunks:
		var ch: CityChunk = city.chunks[k]
		if not is_instance_valid(ch) or not ch.visible or ch.level != CityChunk.Level.FULL or not ch.has_meta("busy_crowd"):
			continue
		for entry: Array in ch.get_meta("busy_crowd"):
			var c := (entry[0] as Rect2).get_center()
			var d := Vector2(c.x - at.x, c.y - at.z).length()
			if d < best_d and int(entry[2]) >= 4:
				best_d = d
				best = ch
				best_entry = entry
	_check(best != null, "a near FULL block has a planned crowd to top up")
	if best == null:
		return
	var ring: Rect2 = best_entry[0]
	for child in best.get_children():
		if child is Pedestrian and (child as Pedestrian).ring == ring and BusyStreets.is_plain_walker(child):
			child.remove_from_group("pedestrian")
			child.queue_free()
	await t.get_tree().process_frame
	var saved_cap: int = city.max_pedestrians
	city.max_pedestrians = CityChunk.count_crowd_room(t.get_tree(), 0) * -1 + 200
	var before := _live(best, ring)
	var total := 0
	for i in 6:
		total += BusyStreets.balance_crowd(city)
		await t.get_tree().process_frame
	var after := _live(best, ring)
	var want := roundi(int(best_entry[2]) * BusyStreets.crowd_factor(BusyStreets.hour_now(city)))
	# Walkers keep crossing between blocks while it fills (Pedestrian's crosswalks hand a walker the
	# next block's ring), so one or two may join the ring on their own: the top-up itself is held
	# to the plan, the live flow gets CROSS_SLACK.
	const CROSS_SLACK := 2
	_check(after > before and after <= maxi(want, before) + CROSS_SLACK, "an emptied near block gets its walkers back (%d -> %d of %d)" % [before, after, want])
	var close_in_view := 0
	var fwd: Vector3 = e[1]
	for child in best.get_children():
		if child is Pedestrian and child.has_meta("busy_topup"):
			var wp := WorldState.to_world((child as Node3D).global_position)
			if BusyStreets.in_view(at, fwd, wp) and Vector2(wp.x - at.x, wp.z - at.z).length() < BusyStreets.crowd_pop_min - 1.0:
				close_in_view += 1
	_check(close_in_view <= 1, "a topped-up walker is not put down close in plain sight (%d)" % close_in_view)
	city.max_pedestrians = saved_cap
	city.trim_pedestrians()


func _live(ch: Node, ring: Rect2) -> int:
	var n := 0
	for child in ch.get_children():
		if child is Pedestrian and (child as Pedestrian).ring == ring and not child.is_queued_for_deletion():
			n += 1
	return n
