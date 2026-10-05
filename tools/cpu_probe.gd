extends SceneTree
## What each per-frame system of the city costs the CPU, headless (the dummy renderer, so this is
## scripts and physics only - which is what the opengl3 counters cannot see).
##
##   godot --headless --path . --script tools/cpu_probe.gd -- --spawn=2359.4,880,0,12,2 --hour=12
##
## Loads the city at the spawn, lets it stream for SETTLE frames (default 400), then measures
## FRAMES frames (default 300) of process + physics time (Performance TIME_PROCESS /
## TIME_PHYSICS_PROCESS, and the frame's wall time) with everything on, and again with each
## system's own process and physics callbacks switched off in turn (its children keep theirs,
## except for the groups, where every member is switched off). The difference is that system's
## per-frame cost. Prints one CPU line per row; run it twice and read the rows that agree.
## SYSTEMS=Birds,LightRail limits the rows.
func _initialize() -> void:
	# One physics step a frame, as in the game at 60 fps.
	Engine.max_fps = 60
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 5:
		await process_frame
	var city: Node = root.find_child("City", false, false)
	if city == null:
		city = root.get_child(root.get_child_count() - 1)
	var settle := int(_env("SETTLE", "400"))
	var frames := int(_env("FRAMES", "300"))
	for i in settle:
		await process_frame
	var rows: Array = [
		["Birds", "node"], ["LightRail", "node"], ["Emergency", "node"], ["Police", "node"],
		["Ambience", "node"], ["AirTraffic", "node"], ["Weather", "node"], ["DayNight", "node"],
		["Traffic", "node"], ["ReplicaTraffic", "node"], ["City", "self"],
		["pedestrian", "group"], ["vehicle", "group"], ["police", "group"], ["responder", "group"],
		["physics_prop", "group"],
	]
	var only := _env("SYSTEMS", "").split(",", false)
	var base := await _measure(frames)
	_print("all on", base, base)
	for r in rows:
		var key: String = r[0]
		if not only.is_empty() and not only.has(key):
			continue
		var nodes: Array = []
		match r[1]:
			"node":
				var n := city.get_node_or_null(key)
				if n:
					nodes.append(n)
			"self":
				nodes.append(city)
			"group":
				nodes = get_nodes_in_group(key)
		if nodes.is_empty():
			continue
		var saved: Array = []
		for n: Node in nodes:
			saved.append([n, n.is_processing(), n.is_physics_processing()])
			n.set_process(false)
			n.set_physics_process(false)
		var m := await _measure(frames)
		for s in saved:
			var n: Node = s[0]
			if is_instance_valid(n):
				n.set_process(s[1])
				n.set_physics_process(s[2])
		_print("%s off (%d nodes)" % [key, nodes.size()], m, base)
	var again := await _measure(frames)
	_print("all on again", again, base)
	quit()


func _measure(frames: int) -> Array:
	var proc := 0.0
	var phys := 0.0
	var wall := 0.0
	var t := Time.get_ticks_usec()
	var steps0 := Engine.get_physics_frames()
	for i in frames:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var now := Time.get_ticks_usec()
		wall += float(now - t) / 1e6
		t = now
	var steps := maxi(Engine.get_physics_frames() - steps0, 1)
	# Physics as ms per physics STEP (a slow frame runs several), process per frame.
	return [proc * 1000.0 / frames, phys * 1000.0 / frames * float(frames) / float(steps), wall * 1000.0 / frames]


func _print(label: String, m: Array, base: Array) -> void:
	print("CPU %-34s process %6.2f ms  physics/step %6.2f ms  frame %6.2f ms  | saves process %+6.2f physics %+6.2f frame %+6.2f" % [
		label, m[0], m[1], m[2], base[0] - m[0], base[1] - m[1], base[2] - m[2]])


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
