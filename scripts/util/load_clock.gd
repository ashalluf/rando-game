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
	LoadPulse.stage(stage)


## Ends `stage` and prints its line; returns its milliseconds.
static func stop(stage: String) -> float:
	var t0: int = _marks.get(stage, Time.get_ticks_usec())
	_marks.erase(stage)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("LOADING %s: %d ms (at %d ms)" % [stage, roundi(ms), Time.get_ticks_msec()])
	LoadPulse.tick()
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
	print_memory()
	# LOAD_FIRST_MINUTE=<s>: watch what still pops in after the load for that long, then quit.
	# (Loaded by path: the Sfx autoload compiles this script before the other autoloads exist.)
	if OS.get_environment("LOAD_FIRST_MINUTE") not in ["", "0"] and tree:
		load("res://scripts/util/first_minute.gd").call("start", tree)
		return
	if quit_after_load() and tree:
		tree.quit()


## One line of what the load holds (mac-launch): the engine's own heap and the renderer's video
## memory (textures, buffers) - on Apple Silicon the GPU's memory IS the machine's RAM, so a Mac
## with 8 or 16 GB swaps once the two together pass what is free. 0 for video under headless.
static func print_memory() -> void:
	var mb := 1048576.0
	print("LOADING memory: static %d MB (peak %d MB), video %d MB (textures %d MB, buffers %d MB)" % [
			roundi(OS.get_static_memory_usage() / mb), roundi(OS.get_static_memory_peak_usage() / mb),
			roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / mb),
			roundi(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / mb),
			roundi(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / mb)])
