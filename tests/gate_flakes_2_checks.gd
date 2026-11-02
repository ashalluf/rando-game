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
