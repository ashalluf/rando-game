extends SceneTree
## The car radio's station card in the city: the player at the wheel of a car at the spawn, the
## chase camera behind it, the HUD in its CLEAN mode, the radio tuned to RADIO.
##
##   OUT=radio.png RADIO=2 HOUR=21 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/radio/radio_shot.gd --resolution 1280x720 \
##     -- --spawn=2359.4,880,0,12,2 --hour=21 --nohud
##
## Env: OUT png; RADIO station 0..3 or -1 (off); BODY a Vehicle.BodyType (default 8, the
## crossover); YAW / PITCH the chase camera (degrees, relative to the car's heading); FRAMES
## streaming frames before the car (default 60); SETTLE frames after tuning (default 12);
## SHOTS=0,1,2,3,-1 takes one still per station from the one load (OUT gets _<station> added).
## Classes are loaded, never named: this script compiles before the autoloads exist.

func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in _env_int("FRAMES", 60):
		await process_frame
	var scene := current_scene
	var player: Node3D = get_first_node_in_group("player")
	var car: Node3D = load("res://scripts/vehicles/vehicle.gd").new()
	car.call("setup", _env_int("BODY", 8), Color(0.08, 0.09, 0.11), 0)
	scene.add_child(car)
	car.global_position = player.global_position + Vector3(0.0, 1.0, 0.0)
	car.rotation.y = player.rotation.y
	for i in 20:
		await physics_frame
	player.call("enter_vehicle", car)
	for i in 10:
		await process_frame
	var hud := scene.get_node_or_null("DebugHud")
	if hud:
		hud.set("mode", 0)
		hud.call("_apply_mode")
	var rig: Node = player.get("camera_rig")
	if rig and rig.has_method("set_look"):
		rig.call("set_look", rad_to_deg(car.rotation.y) + _env_float("YAW", 0.0), _env_float("PITCH", -10.0))
	var radio: Node = get_root().get_node_or_null("CarRadio")
	var out := OS.get_environment("OUT")
	if out == "":
		out = "radio_shot.png"
	var shots := OS.get_environment("SHOTS").split(",", false)
	if shots.is_empty():
		shots = [OS.get_environment("RADIO") if OS.get_environment("RADIO") != "" else "2"]
	for sh in shots:
		var st := int(sh)
		if radio:
			radio.call("tune", st)
			radio.set("card_age", 0.0)
		for i in _env_int("SETTLE", 12):
			await process_frame
		if radio:
			radio.set("card_age", 0.5) # hold the card up for the shot
		var path := out if shots.size() == 1 else out.get_basename() + "_%s.png" % sh.replace("-", "m")
		get_root().get_texture().get_image().save_png(path)
		var np: Variant = radio.call("now_playing") if radio else {}
		print("saved ", path, " station ", st, " ", np)
	quit()


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback


func _env_float(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
