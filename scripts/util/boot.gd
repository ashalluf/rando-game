extends Node
## The main scene (mac-launch, docs/HANDOFF.md "The Mac launch"): the loading picture at once
## (LoadPulse), then the game's scripts compiled a few at a time with a frame between, then the
## city scene. Loading city.tscn compiles the whole game's GDScript (~650 scripts: ~20 s on a
## 4-core box, more in the editor) in ONE call, and as the main scene that ran before the window
## had drawn a single frame. Here each script is loaded on its own, its dependencies first (a
## post-order over the class names each file mentions), so each load() compiles about one file and
## the picture keeps moving; the city's load then finds them compiled. The city's own _ready()
## takes over the same picture (LoadPulse.begin()).
##
## Most of the game is ONE dependency cycle (city_chunk, building, vehicle, aircraft, ... name each
## other), and load() cannot split a cycle: the first script of it compiles the whole cycle in one
## call (15.5 s of the 18 s on the 4-core box, measured). So the bar moves through the ~200 scripts
## outside it and then the picture holds still, but stays up, through that one call; the window
## never shows the engine's splash or a black frame.
##
## A loader THREAD was tried first (ResourceLoader.load_threaded_request): with the codebase's
## cyclic preloads (city_chunk.gd <-> building.tscn) it handed back a scene whose buildings would
## not instance, and a second run deadlocked. Main thread only.
##
## Straight to the city where there is no picture to show (headless, the web, --noload / --nohud,
## LOAD_PULSE=0) or with BOOT_COMPILE=0.

const CITY := "res://scenes/levels/city.tscn"
## Milliseconds of loading between two frames.
const BUDGET_MS := 60

var _order: PackedStringArray = []
var _next: int = 0
var _running := false


func _ready() -> void:
	LoadClock.at("boot")
	var picture := LoadPulse.supported() and not _harness()
	if picture:
		LoadPulse.begin_picture(get_viewport())
	if not picture or OS.get_environment("BOOT_COMPILE") == "0":
		get_tree().change_scene_to_file.call_deferred(CITY)
		return
	LoadClock.start("compile the game")
	_order = compile_order()
	_running = true


func _process(_delta: float) -> void:
	if not _running:
		return
	var t0 := Time.get_ticks_msec()
	while _next < _order.size() and Time.get_ticks_msec() - t0 < BUDGET_MS:
		var a := Time.get_ticks_msec()
		load(_order[_next])
		var ms := Time.get_ticks_msec() - a
		if ms > 2000:
			print("LOADING compile: %s took %d ms (the game's big dependency cycle)" % [_order[_next].get_file(), ms])
		_next += 1
	LoadPulse.note("%d / %d scripts" % [_next, _order.size()])
	LoadPulse.paint()
	if _next < _order.size():
		return
	_running = false
	LoadPulse.note("")
	LoadClock.stop("compile the game")
	# (Every shader file queued here, ahead of the city, was tried: it is a flood of its own -
	# ~300 shaders' variant groups on the workers - and a landmark's new material waited behind it.)
	get_tree().change_scene_to_file.call_deferred(CITY)


## Every global class's script, dependencies before the scripts that name them (a depth-first
## post-order over the capitalised words of each file that are other classes' names). A file whose
## source cannot be read (an export's binary tokens) keeps its place with no dependencies: the
## order is then coarser, never wrong - load() compiles whatever a script needs either way.
static func compile_order() -> PackedStringArray:
	var path_of := {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var p := str(c.get("path", ""))
		if p.ends_with(".gd"):
			path_of[str(c["class"])] = p
	var words := RegEx.new()
	words.compile("\\b[A-Z][A-Za-z0-9_]+\\b")
	var deps := {}
	for cls: String in path_of:
		var src := FileAccess.get_file_as_string(path_of[cls])
		var mine := {}
		for m in words.search_all(src):
			var w := m.get_string()
			if w != cls and path_of.has(w):
				mine[w] = true
		deps[cls] = mine.keys()
	var out := PackedStringArray()
	var state := {} # 1 visiting, 2 done
	var names := path_of.keys()
	names.sort()
	for root: String in names:
		if state.has(root):
			continue
		# Iterative DFS (the class graph is deep: recursion would be hundreds of frames).
		var stack: Array = [[root, 0]]
		state[root] = 1
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var d: Array = deps[top[0]]
			if top[1] < d.size():
				var n: String = d[top[1]]
				top[1] += 1
				if not state.has(n):
					state[n] = 1
					stack.append([n, 0])
			else:
				stack.pop_back()
				state[top[0]] = 2
				out.append(path_of[top[0]])
	return out


## The screenshot harnesses (--noload / --nohud) see no loading picture (CityStreamer's rule).
static func _harness() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--noload" or arg == "--nohud":
			return true
	return false
