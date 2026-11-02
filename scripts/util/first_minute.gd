extends Node
## What the first minute of play still has to do after the loading screen lifts (fleet wave 4,
## loading-first-frame; docs/HANDOFF.md "The first minute"). `LOAD_FIRST_MINUTE=<seconds>` in the
## environment: LoadClock.loaded() adds this node instead of quitting, and it prints one line a
## second, then a summary, then quits (with LOAD_QUIT=1) - so tools/load_time/load_time.sh measures
## the load AND what pops in after it:
##
##   FIRSTMIN t=<s> frame=<median ms>/<worst ms> pending=<FULL>/<LOD> missing=<FULL>/<LOD>
##            swaps=<installed this second> sky=<tiles building or due> cars=<street>/<freeway>
##            queued=<car spawns queued> peds=<walkers>
##
## "missing" is what the streamer's window wants that is not standing yet (a block drawn by the far
## city or an older level meanwhile); "swaps" is chunks that appeared or changed level that second
## (each a visible pop-in); "sky" is far-city work still to do round the eye. Nothing here changes
## the game: it only reads the streamer, the far city and the traffic.

var seconds: float = 60.0
var _city: Node
var _t: float = 0.0
var _next: float = 1.0
var _frames: Array = []
var _levels: Dictionary = {}
var _swaps: int = 0
var _swap_total: int = 0
var _last_swap: float = 0.0
var _first_full_traffic: float = -1.0
var _worst: float = 0.0
var _over: float = 0.0


## Adds the monitor when LOAD_FIRST_MINUTE is set; true when it did (the caller then does not quit).
static func start(tree: SceneTree) -> bool:
	var s := OS.get_environment("LOAD_FIRST_MINUTE")
	if s == "" or s == "0" or tree == null:
		return false
	var m: Node = load("res://scripts/util/first_minute.gd").new()
	m.name = "FirstMinute"
	m.set("seconds", maxf(s.to_float(), 1.0))
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(m)
	return true


func _ready() -> void:
	_city = get_tree().get_first_node_in_group("city")
	_levels = _snapshot()


func _snapshot() -> Dictionary:
	var out := {}
	if _city == null:
		return out
	var chunks: Dictionary = _city.get("chunks")
	for k in chunks:
		var c: Node = chunks[k]
		if is_instance_valid(c):
			out[k] = int(c.get("level"))
	return out


func _process(delta: float) -> void:
	if _city == null or not is_instance_valid(_city):
		return
	var ms := delta * 1000.0
	_frames.append(ms)
	_worst = maxf(_worst, ms)
	_over += maxf(ms - 50.0, 0.0)
	_t += delta
	var now := _snapshot()
	for k in now:
		if not _levels.has(k) or _levels[k] != now[k]:
			_swaps += 1
			_swap_total += 1
			_last_swap = _t
	_levels = now
	if _t < _next:
		return
	_next += 1.0
	print(_line())
	_frames.clear()
	_swaps = 0
	if _t >= seconds:
		print("FIRSTMIN summary: %d swaps, the last at %.1f s; traffic settled at %s; worst frame %d ms; %d ms over 50 ms frames" % [
				_swap_total, _last_swap, ("%.1f s" % _first_full_traffic) if _first_full_traffic >= 0.0 else "never",
				roundi(_worst), roundi(_over)])
		if LoadClock.quit_after_load():
			get_tree().quit()
		set_process(false)


func _line() -> String:
	var sorted := _frames.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	var worst: float = sorted.back() if not sorted.is_empty() else 0.0
	var pend := Vector2i.ZERO
	var pending: Dictionary = _city.get("_pending")
	for k in pending:
		if int(pending[k].get("level")) == CityChunk.Level.FULL:
			pend.x += 1
		else:
			pend.y += 1
	var miss := _missing()
	var sky := -1
	var skyline: Node = _city.get("_skyline")
	if skyline:
		var work: Dictionary = skyline.get("_work")
		sky = work.size() + (0 if skyline.call("complete", _city.get("_eye")) else 1)
	var cars := Vector2i(-1, -1)
	var queued := -1
	var traffic := _city.get_node_or_null("Traffic")
	if traffic:
		cars = Vector2i((traffic.get("cars") as Array).size(), (traffic.get("freeway_cars") as Array).size())
		queued = 0
		for q: Array in traffic.get("_spawn_queues"):
			queued += q.size()
		# Settled: the upkeep has nothing left to build (the first second its queues are empty).
		if _first_full_traffic < 0.0 and queued == 0:
			_first_full_traffic = _t
	var peds := get_tree().get_nodes_in_group("pedestrian").size()
	return "FIRSTMIN t=%d frame=%d/%d pending=%d/%d missing=%d/%d swaps=%d sky=%d cars=%d/%d queued=%d peds=%d" % [
			roundi(_t), roundi(med), roundi(worst), pend.x, pend.y, miss.x, miss.y, _swaps, sky,
			cars.x, cars.y, queued, peds]


## Blocks the window wants at a level that is not standing (FULL, LOD), counted the way
## CityStreamer.update_streaming() decides them (its own reaches; a cheap copy of the loop).
func _missing() -> Vector2i:
	var out := Vector2i.ZERO
	var plan: CityPlan = _city.get("plan")
	if plan == null:
		return out
	var lead: Vector2 = _city.get("_lead")
	var center := plan.block_index_at(lead)
	var lod_r: int = _city.get("lod_radius_blocks")
	var load_r: int = _city.get("load_radius_blocks")
	var lod_reach: float = _city.call("lod_reach_metres")
	var full_reach: float = _city.call("full_reach_metres")
	var chunks: Dictionary = _city.get("chunks")
	for dx in range(-lod_r, lod_r + 1):
		for dz in range(-lod_r, lod_r + 1):
			var ring := maxi(absi(dx), absi(dz))
			var k := Vector2i(center.x + dx, center.y + dz)
			var dist: float = _city.call("_block_distance", k, lead)
			if ring > load_r and dist > lod_reach:
				continue
			var want := CityChunk.Level.FULL if ring <= load_r and dist <= full_reach else CityChunk.Level.LOD
			var c: Node = chunks.get(k)
			if c == null or int(c.get("level")) != want:
				if want == CityChunk.Level.FULL:
					out.x += 1
				else:
					out.y += 1
	return out
