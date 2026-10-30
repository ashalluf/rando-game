class_name LoadClock
extends RefCounted
## Times the start of a session, stage by stage, so a change to what loads can be measured rather
## than guessed (docs/HANDOFF.md, "Load time"). Every stage prints one line:
##
##   LOADING <stage>: <ms> ms (at <ms since the engine started> ms)
##
## `tools/load_time/load_time.sh` runs the game (opengl3 under Xvfb, or headless) and collects
## them. `LOAD_QUIT=1` in the environment quits the game as soon as the loading screen is done
## (or, with no loading screen - headless, `--noload` - once the city has streamed in), so a run
## measures the load and nothing else.

static var _marks: Dictionary = {}
## LOAD_PROFILE=1: CityChunk's build steps are timed by name (profile_step) and the totals
## printed at the end of the load, slowest first.
static var profiling: bool = OS.get_environment("LOAD_PROFILE") == "1"
## "FULL <step>" / "LOD <step>" -> [microseconds, calls]
static var _steps: Dictionary = {}


## Starts timing `stage` (a name; nest them freely).
static func start(stage: String) -> void:
	_marks[stage] = Time.get_ticks_usec()


## Ends `stage` and prints its line; returns its milliseconds.
static func stop(stage: String) -> float:
	var t0: int = _marks.get(stage, Time.get_ticks_usec())
	_marks.erase(stage)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("LOADING %s: %d ms (at %d ms)" % [stage, roundi(ms), Time.get_ticks_msec()])
	return ms


## Prints when `event` happened (ms since the engine started), with no duration.
static func at(event: String) -> void:
	print("LOADING %s (at %d ms)" % [event, Time.get_ticks_msec()])


## True when the run should end after loading (LOAD_QUIT=1).
static func quit_after_load() -> bool:
	return OS.get_environment("LOAD_QUIT") == "1"


## Runs one chunk build step, timing it under its method's name; returns whether it finished
## (a step that returns false has more to do).
static func profile_step(step: Callable, full: bool) -> bool:
	var t0 := Time.get_ticks_usec()
	var done: bool = step.call() != false
	var key := ("FULL " if full else "LOD ") + str(step.get_method())
	var e: Array = _steps.get(key, [0, 0])
	e[0] += Time.get_ticks_usec() - t0
	e[1] += 1
	_steps[key] = e
	return done


## Prints the step totals (LOAD_PROFILE=1), slowest first.
static func print_profile(limit: int = 40) -> void:
	var keys := _steps.keys()
	keys.sort_custom(func(a, b): return _steps[a][0] > _steps[b][0])
	for i in mini(limit, keys.size()):
		var e: Array = _steps[keys[i]]
		print("LOADING step %s: %d ms in %d calls" % [keys[i], e[0] / 1000, e[1]])


## Called once the game is playable: prints the total and quits when asked to.
static func loaded(tree: SceneTree) -> void:
	if profiling:
		print_profile()
	print("LOADING total: %d ms (at %d ms)" % [Time.get_ticks_msec(), Time.get_ticks_msec()])
	if quit_after_load() and tree:
		tree.quit()
