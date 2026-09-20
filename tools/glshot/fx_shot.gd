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
##
## Do not count frames here: a frame takes most of a second under llvmpipe and the length varies,
## so "wait five frames" lands anywhere from the first millisecond of the blast to well after it.
## Slowing the clock and then waiting on real elapsed time puts the shot where it was asked for.
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
	var at := cam.global_position + forward * float(_env_int("FX_AT", 14))
	at.y = player.global_position.y
	# Keep this tiny. Each software-rendered frame takes most of a second, so even a modest time
	# scale advances the effect past the fireball in one or two frames and every shot lands on an
	# empty street. 0.004 gives roughly a frame per 4 ms of effect time.
	var scale := float(OS.get_environment("TIME_SCALE")) if OS.get_environment("TIME_SCALE") != "" else 0.004
	var want := float(OS.get_environment("FX_TIME")) if OS.get_environment("FX_TIME") != "" else 0.35
	Engine.time_scale = scale
	WeaponFX.explosion(player, at, float(_env_int("FX_RADIUS", 9)))
	# Game time runs at `scale` of real time, so wait out want/scale seconds of wall clock.
	var started := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - started) * 0.001 * scale < want:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "fx_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
