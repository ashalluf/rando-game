extends SceneTree
## Watches the valet stands round the player in the running city (headless, a few minutes):
## every 5 s of game time prints each stand's queue, service state and counters.
##   godot --headless --path . --script tools/valets/live.gd -- --spawn=x,z,yaw,pitch [--hour=20]
## SECONDS=game seconds to watch (default 150).

func _initialize() -> void:
	var hour := 20.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	var vs: GDScript = load("res://scripts/world/valets.gd")
	vs.set("force_hour", hour)
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 30:
		await process_frame
	var secs := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 150.0
	var t0 := Engine.get_physics_frames()
	var next := 0.0
	while true:
		await physics_frame
		var t := float(Engine.get_physics_frames() - t0) / float(Engine.physics_ticks_per_second)
		if t >= next:
			next += 5.0
			var stands := get_nodes_in_group("valet_stand")
			var line := "T=%.0f stands=%d" % [t, stands.size()]
			for s in stands:
				var front: Variant = s.get("front")
				var fd := -1.0
				if front != null and is_instance_valid(front):
					fd = 0.0
				line += " | %s q=%d serve=%d called=%d placed=%d served=%d back=%d away=%d valets=%d" % [String(s.name).trim_prefix("ValetStand_"), (s.get("queue") as Array).size(), int(s.get("serve")), int(s.get("called")), int(s.get("placed")), int(s.get("served")), int(s.get("returned")), (s.get("away") as Array).size(), (s.get("valets") as Array).size()]
			print(line)
		if t > secs:
			break
	quit()
