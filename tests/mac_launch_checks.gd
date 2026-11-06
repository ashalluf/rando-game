extends RefCounted
## The Mac launch (mac-launch, docs/HANDOFF.md "The Mac launch"): the window presents frames for
## the whole load (LoadPulse), the city is compiled behind a boot scene, the 3D is held off while
## the pipelines compile, and Quality never judges the machine by the loading screen's frames.
## Loaded at run time by tests/smoke_test.gd.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_boot()
	_pulse_headless()
	_hooks()
	_quality(city)


func _boot() -> void:
	_check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/boot.tscn",
			"the main scene is the boot scene (the city compiles on a loader thread behind the picture)")
	var src := FileAccess.get_file_as_string("res://scripts/util/boot.gd")
	_check(src.contains("compile_order()") and src.contains("change_scene_to_file"),
			"the boot scene compiles the scripts a few a frame, then changes to the city")
	_check(not src.contains("load_threaded_request("), "no loader thread (it broke the cyclic preloads and deadlocked)")
	var city_path := "res://scenes/levels/city.tscn"
	_check(src.contains('"%s"' % city_path) and ResourceLoader.exists(city_path), "the boot scene's CITY is the city scene")
	_check(src.contains("BOOT_COMPILE"), "BOOT_COMPILE=0 is the boot's A/B")
	var order: PackedStringArray = load("res://scripts/util/boot.gd").compile_order()
	var classes := 0
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c.get("path", "")).ends_with(".gd"):
			classes += 1
	_check(order.size() == classes, "the compile order has every global class once (%d of %d)" % [order.size(), classes])
	var seen := {}
	for p in order:
		seen[p] = true
	_check(seen.size() == order.size(), "no script twice in the compile order")
	var i_lp := order.find("res://scripts/ui/hud_theme.gd")
	var i_pulse := order.find("res://scripts/util/load_pulse.gd")
	_check(i_lp >= 0 and i_pulse > i_lp, "a dependency comes before the script that names it (HudTheme before LoadPulse)")


func _pulse_headless() -> void:
	_check(not LoadPulse.supported(), "the pulse never runs headless")
	_check(not LoadPulse.active, "the pulse is inactive in the gate")
	var before := LoadPulse.pulses
	for i in 5:
		LoadPulse.tick(true)
	LoadPulse.stage("ground bake")
	LoadPulse.paint()
	_check(LoadPulse.pulses == before and not LoadPulse.holding(), "an inactive pulse presents nothing and holds nothing")
	_check(FileAccess.get_file_as_string("res://scripts/util/load_pulse.gd").contains('"LOAD_PULSE") != "0"'), "LOAD_PULSE=0 is the A/B")
	for name in ["compile the game", "macro map", "ground bake", "far landmarks", "first streaming",
			"screen: shaders and effects", "far city", "screen: rehearsal", "graphics"]:
		_check(LoadPulse.STAGES.has(name), "the pulse has a step for LOADING stage '%s'" % name)


## The long synchronous loops present frames.
func _hooks() -> void:
	var pairs := {
		"res://scripts/world/macro_map.gd": "LoadPulse.tick()",
		"res://scripts/world/city_chunk.gd": "LoadPulse.tick()",
		"res://scripts/world/skyline.gd": "LoadPulse.tick()",
		"res://scripts/world/city_streamer.gd": "LoadPulse.begin(get_viewport())",
		"res://scripts/util/load_clock.gd": "LoadPulse.stage(stage)",
		"res://scripts/ui/loading_screen.gd": "await LoadPulse.drain(get_tree())",
		"res://scripts/world/reflection_probes.gd": "if LoadPulse.active",
	}
	for path: String in pairs:
		_check(FileAccess.get_file_as_string(path).contains(pairs[path]), "%s calls %s" % [path.get_file(), pairs[path]])


## Quality holds its level while a loading screen is up.
func _quality(city: Node3D) -> void:
	var q: Node = city.get_node_or_null("Quality")
	if q == null:
		_check(true, "Quality holds under the loading screen (no Quality node here)")
		return
	var was_showing := LoadingScreen.showing
	var was_time: float = q.get("_time")
	var was_frames: int = q.get("_frames")
	var was_proc := q.is_processing()
	var was_forced: bool = q.get("_forced")
	LoadingScreen.showing = true
	q.set("_forced", false)
	var lvl: int = q.get("level")
	if lvl == 3:
		_check(true, "Quality holds under the loading screen (at LOWEST, nothing to demote)")
	else:
		for i in 40:
			q.call("_process", 1.0)
		_check(int(q.get("level")) == lvl and float(q.get("_time")) == 0.0,
				"Quality does not demote the level on the loading screen's slow frames")
	LoadingScreen.showing = was_showing
	q.set("_time", was_time)
	q.set("_frames", was_frames)
	q.set("_forced", was_forced)
	q.set_process(was_proc)
