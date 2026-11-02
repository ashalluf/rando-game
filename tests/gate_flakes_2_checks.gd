extends RefCounted
## The gate's intermittent failures, wave 5 (docs/HANDOFF.md "The gate's intermittent failures,
## wave 5") for tests/smoke_test.gd: the causes fixed outside a check file.
## - CityStreamer drops a build left pending at the other level once the block already stands at
##   the wanted one: before, it finished a few frames later and was installed OVER the chunk (the
##   spawn block's FULL chunk swapped for a LOD one mid-file, then rebuilt FULL).
## Stages a pending build on the home block and takes it away again.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	await _stale_build(city)
	_exit_hold(city)


func _stale_build(city: Node3D) -> void:
	var player := _t.get_tree().get_first_node_in_group("player") as Node3D
	var plan: CityPlan = city.get("plan")
	if player == null or plan == null:
		_t._check(false, "gate flakes 2: the city has a player and a plan")
		return
	city.call("update_streaming", true)
	var wp := WorldState.to_world(player.global_position)
	var k: Vector2i = plan.block_index_at(Vector2(wp.x, wp.z))
	var chunks: Dictionary = city.get("chunks")
	var pending: Dictionary = city.get("_pending")
	var home: Variant = chunks.get(k)
	_t._check(home is CityChunk and int((home as CityChunk).level) == CityChunk.Level.FULL,
		"gate flakes 2: the block under the player stands FULL")
	if not (home is CityChunk):
		return
	# What a trip away leaves behind: a LOD build of the home block, started while the window was
	# elsewhere and not finished when the player came back.
	city.call("_start_build", k, CityChunk.Level.LOD)
	_t._check(pending.has(k), "gate flakes 2: a LOD build of the home block is pending (staged)")
	var before: int = CityStreamer.stale_builds_cancelled
	city.call("update_streaming", false)
	_t._check(not pending.has(k) and CityStreamer.stale_builds_cancelled == before + 1,
		"gate flakes 2: a pending build at the wrong level is dropped once the block stands at the wanted one (pending %s)" % pending.has(k))
	for i in 20:
		await _t.get_tree().physics_frame
	_t._check(is_instance_valid(home) and chunks.get(k) == home,
		"gate flakes 2: the home block's chunk is the same node 20 ticks later (not replaced)")
	# The same with the immediate path (stage_home's): nothing pending survives it either.
	city.call("_start_build", k, CityChunk.Level.LOD)
	city.call("update_streaming", true)
	_t._check(not pending.has(k) and chunks.get(k) == home,
		"gate flakes 2: update_streaming(true) drops it too and keeps the chunk")


## A freeway car in the outer lane with its exit 500 m on, behind a slower car: it stays in the
## lane (EXIT_HOLD); with the hold off it pulls out to pass, which is how it missed its off-ramp.
func _exit_hold(city: Node3D) -> void:
	var traffic: Node = city.get_node_or_null("Traffic")
	var plan: CityPlan = city.get("plan")
	var fw: Freeway = plan.macro.freeway if plan and plan.macro else null
	if traffic == null or fw == null:
		_t._check(true, "gate flakes 2: no freeway to hold an exit on (skipped)")
		return
	var ri := -1
	var off := {}
	for r_i in fw.routes.size():
		for r: Dictionary in TrafficAI.ramps_of(traffic, fw, r_i):
			if not bool(r.on) and off.is_empty() and float(r.t) > 700.0:
				off = r
				ri = r_i
	if off.is_empty():
		_t._check(true, "gate flakes 2: no off-ramp to hold an exit for (skipped)")
		return
	var outer := Freeway.LANES - 1
	var width := float(fw.routes[ri].width)
	var me: Vehicle = traffic.call("place_freeway_car", ri, float(off.t) - 500.0, 1, -1, 25.0)
	var slow: Vehicle = traffic.call("place_freeway_car", ri, float(off.t) - 470.0, 1, -1, 8.0)
	for c: Vehicle in [me, slow]:
		c.traffic.li = outer
		c.traffic.lane = Freeway.lane_fraction(width, outer)
	slow.traffic.v = 8.0
	me.traffic.v = 25.0
	me.traffic.exit = true
	me.traffic.ai = true
	var held := []
	for hold: bool in [true, false]:
		TrafficAI.EXIT_HOLD = hold
		for k in ["lc_from", "lc_to", "lc_p", "lc_dur", "lc_src", "sig", "lc_next"]:
			me.traffic.erase(k)
		me.traffic.li = outer
		me.traffic.lane = Freeway.lane_fraction(width, outer)
		# No groups: every other lane is empty, so a pass is always open.
		TrafficAI.freeway_think(traffic, fw, me, slow, {}, 10.0)
		held.append(not me.traffic.has("lc_from"))
	TrafficAI.EXIT_HOLD = true
	for c: Vehicle in [me, slow]:
		(traffic.get("freeway_cars") as Array).erase(c)
		traffic.call("_retire", c)
	_t._check(held[0] and not held[1],
		"gate flakes 2: within a kilometre of its exit a car behind a slower one keeps its lane (held %s; with EXIT_HOLD=0 %s)" % [held[0], held[1]])
