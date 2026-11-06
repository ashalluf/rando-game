extends Node
## What a frame of the live city costs the gate, headless: wall time per process frame and per
## physics tick, Performance's process and physics times, the steps run per frame. A scene (so the
## autoloads exist): godot --headless --path . res://tools/gate/frame_probe.tscn
## STEPS=8,16 measures again with Engine.max_physics_steps_per_frame at each value.

var _ticks := 0


func _ready() -> void:
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	_ticks += 1


func _run() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(city)
	for i in int(OS.get_environment("SETTLE") if OS.get_environment("SETTLE") != "" else "200"):
		await get_tree().process_frame
	var frames := 150
	for steps in (OS.get_environment("STEPS") if OS.get_environment("STEPS") != "" else "8").split(","):
		Engine.max_physics_steps_per_frame = int(steps)
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		var k0 := _ticks
		var proc := 0.0
		var phys := 0.0
		for i in frames:
			await get_tree().process_frame
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var wall := (Time.get_ticks_usec() - t0) / 1e6
		var ticks := _ticks - k0
		print("FRAME steps %s: %.3f s/frame, %.1f ticks/frame, %.4f s/tick, proc %.4f phys %.4f (per frame avg)" % [
			steps, wall / frames, float(ticks) / frames, wall / maxf(ticks, 1), proc / frames, phys / frames])
	get_tree().quit(0)
