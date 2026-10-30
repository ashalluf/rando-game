extends SceneTree
## Screenshots a weapon effect in the city with the real OpenGL renderer, the same way
## tools/glshot/city_shot.gd screenshots the world. Effects last under a second, and a frame
## under llvmpipe takes most of a second, so the clock is slowed right down before the effect is
## triggered; otherwise every shot catches an empty street after the fireball has gone.
##
##   OUT=boom.png FX_AT=14 FX_RADIUS=9 FX_TIME=0.35 FRAMES=70 \
##     LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/fx_shot.gd --resolution 960x540 -- --spawn=650,300,0,-4 --hour=11 --nohud
##
## Env: OUT png path, FRAMES streaming frames to wait first, FX_AT meters in front of the camera,
## FX_RADIUS blast radius, FX_TIME how many seconds into the effect to photograph (0.35 catches
## the fireball at full size, 1.8 catches the smoke), TIME_SCALE the slow-motion factor.
## FX_TIMES=0.05,0.2,1,4,12 shoots a strip from ONE blast: `<OUT stem>_t<seconds>.png` each
## (past `FX_FAST_AFTER` seconds, 1.0 by default, the clock runs at LATE_SCALE, 3.0 by default, so
## the smoke column's 12 s do not take an hour). FX_CAR=1 explodes a parked car there instead
## (CarDamage.explode(): the fuel fireball and the toss); FX_SIDE shifts the blast sideways (m).
##
## The wait counts the effect's own elapsed time (the sum of frame deltas), because Godot caps
## each frame at eight physics ticks however long the software frame really took.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in _env_int("FRAMES", 70):
		await process_frame
	var player: Node3D = get_first_node_in_group("player")
	var cam := get_root().get_camera_3d()
	if player == null or cam == null:
		push_error("no player or camera")
		quit(1)
		return
	var forward := -cam.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var at := cam.global_position + forward * float(_env_int("FX_AT", 14)) + forward.cross(Vector3.UP) * float(_env_int("FX_SIDE", 0))
	at.y = player.global_position.y
	# Godot caps a frame at eight physics ticks (0.133 s) however long it really took, so the
	# effect advances 0.133 s x TIME_SCALE per frame: the default 0.375 is 0.05 s a frame.
	var scale := float(OS.get_environment("TIME_SCALE")) if OS.get_environment("TIME_SCALE") != "" else 0.375
	var late := float(OS.get_environment("LATE_SCALE")) if OS.get_environment("LATE_SCALE") != "" else 3.0
	var fast_after := float(OS.get_environment("FX_FAST_AFTER")) if OS.get_environment("FX_FAST_AFTER") != "" else 1.0
	var times: Array[float] = []
	if OS.get_environment("FX_TIMES") != "":
		for s in OS.get_environment("FX_TIMES").split(","):
			times.append(float(s))
	else:
		times.append(float(OS.get_environment("FX_TIME")) if OS.get_environment("FX_TIME") != "" else 0.35)
	var out := OS.get_environment("OUT")
	if out == "":
		out = "fx_shot.png"
	Engine.time_scale = scale
	if OS.get_environment("FX_CAR") == "1":
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
		player.get_parent().add_child(car)
		car.global_position = at + Vector3.UP * 0.6
		car.rotation.y = randf() * TAU
		for i in 3:
			await process_frame
		car.call("damage_state").explode()
	else:
		# Loaded by path: naming a class here compiles it before the autoloads exist.
		load("res://scripts/weapons/weapon_fx.gd").explosion(player, at, float(_env_int("FX_RADIUS", 9)))
	# Count the effect's own time, not the wall clock: that cap means game time does NOT run at
	# `scale` of real time, and waiting on the wall clock stopped every shot in the first few
	# milliseconds of the blast, before the fireball had grown.
	var elapsed := 0.0
	for want in times:
		while elapsed < want:
			Engine.time_scale = late if elapsed >= fast_after else scale
			await process_frame
			elapsed += get_root().get_process_delta_time()
		var path := out
		if times.size() > 1:
			path = out.get_basename() + "_t%05.2f.png" % want
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path, " at ", elapsed)
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
