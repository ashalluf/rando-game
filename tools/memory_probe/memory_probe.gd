extends Node
## City memory probe: loads scenes/levels/city.tscn the way tests/smoke_test.gd does, steps
## PROBE_TICKS physics frames (300) and prints VmHWM / VmRSS (/proc/self/status) and Godot's own
## static memory at each stage. Run headless, alone (a city is GBs):
##   godot --headless --path . res://tools/memory_probe/memory_probe.tscn
## Turn a feature off with its switch (CONSTRUCTION=0 ...) to see what it costs.
## PROBE_TICKS=n steps more; PROBE_EVERY=n prints every n ticks (30).


func _ready() -> void:
	_run.call_deferred()


func _mem(stage: String) -> void:
	var hwm := ""
	var rss := ""
	# /proc files report a length of 0, so read them line by line rather than get_as_text().
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	while f and not f.eof_reached():
		var line := f.get_line()
		if line == "":
			break
		if true:
			if line.begins_with("VmHWM:"):
				hwm = line.substr(6).strip_edges()
			elif line.begins_with("VmRSS:"):
				rss = line.substr(6).strip_edges()
	print("MEM %-28s HWM %12s  RSS %12s  static %7.0f MB  objects %d  t %.1f s" % [stage, hwm, rss,
		OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT),
		Time.get_ticks_msec() / 1000.0])


func _run() -> void:
	_mem("start")
	var packed: PackedScene = load("res://scenes/levels/city.tscn")
	_mem("city loaded")
	var city: Node3D = packed.instantiate()
	_mem("instantiated")
	get_tree().root.add_child(city)
	_mem("added")
	var ticks := int(OS.get_environment("PROBE_TICKS")) if OS.get_environment("PROBE_TICKS") != "" else 300
	var every := int(OS.get_environment("PROBE_EVERY")) if OS.get_environment("PROBE_EVERY") != "" else 30
	for i in ticks:
		await get_tree().physics_frame
		if (i + 1) % every == 0:
			_mem("tick %d" % (i + 1))
	_mem("end")
	get_tree().quit(0)
