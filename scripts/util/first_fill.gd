class_name FirstFill
extends RefCounted
## The street's traffic, filled behind the loading shade (fleet wave 4, loading-first-frame;
## docs/HANDOFF.md "The first minute").
##
## TrafficManager builds at most `builds_per_frame` (1) car a frame, so a slow machine never pays
## for a dozen 35 ms car builds in one frame of play. But a launch hands it an EMPTY city: the
## loading screen holds a few dozen frames, so play started with 4 street cars of a ~40-car
## target and 2 on the freeway, and the next 15-20 s were cars popping into sight one a frame
## round the camera (FIRST_MINUTE=40 on tools/load_time/load_time.sh measured it). The same first
## fill done while the shade is still up costs the same builds and nobody sees them land.
##
## `traffic()` runs TrafficManager's own upkeep (the same spawns, from the same queues, on its own
## rng) as often as it takes, with no per-frame cap, until the street, the freeway and the airport
## loop hold what they ask for or `budget_usec` runs out. Nothing new is decided here: these are
## the cars the first 20 seconds of play would have built. `FIRST_FILL=0` in the environment turns
## it off (the A/B).

static var enabled: bool = OS.get_environment("FIRST_FILL") != "0"
## Upkeep rounds before giving up on a target the city cannot meet (a closed road, a quiet hour).
const MAX_ROUNDS := 12


## Fills `tm`'s traffic now. Returns [street cars, freeway cars, cars built] for the log.
static func traffic(tm: Node, budget_usec: int = 20000000) -> Array:
	if not enabled or tm == null or not is_instance_valid(tm) or bool(tm.get("staged")):
		return [0, 0, 0]
	if tm.get("plan") == null:
		return [0, 0, 0]
	if tm.get("_player") == null:
		tm.set("_player", tm.get_tree().get_first_node_in_group("player"))
		if tm.get("_player") == null:
			return [0, 0, 0]
	var t0 := Time.get_ticks_usec()
	var built := 0
	var last := -1
	for round in MAX_ROUNDS:
		var queues: Array = tm.get("_spawn_queues")
		for q: Array in queues:
			q.clear()
		tm.call("_maintain")
		tm.call("_maintain_freeway")
		var ran := 0
		for q: Array in queues:
			while not q.is_empty():
				(q.pop_front() as Callable).call()
				ran += 1
				if Time.get_ticks_usec() - t0 > budget_usec:
					break
		built += ran
		var total := (tm.get("cars") as Array).size() + (tm.get("freeway_cars") as Array).size() \
				+ (tm.get("loop_cars") as Array).size()
		# Done when an upkeep round queues nothing more, or nothing it queued could be placed.
		if ran == 0 or total == last or Time.get_ticks_usec() - t0 > budget_usec:
			break
		last = total
	return [(tm.get("cars") as Array).size(), (tm.get("freeway_cars") as Array).size(), built]
