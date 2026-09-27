extends SceneTree
## Proves the motion blur (MotionBlurEffect) really runs, through the REAL Forward+ renderer
## under lavapipe - the city does not fit in this box's memory there, so this is a small street
## built in code: a checker road, two rows of columns, far blocks, a sky, and a "player" (a
## capsule with a gun) standing where the third-person camera looks, moving with the camera.
##
##   OUT=/tmp/mb.png MODE=forward MB=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/motion_blur_shot.gd --resolution 960x540
##
## Env: OUT png path; MODE forward (flying down the street at SPEED m/s), strafe (sideways),
## whip (the camera orbiting the player at RATE rad/s - a mouse flick), object (a still camera,
## a car-sized box crossing at SPEED), still (nothing moves: must equal MB=0 exactly);
## MB=0 builds no effect (the "before"); AA=taa (default) | fsr (0.6 scale, FSR 2.2, whose
## velocity buffer holds only moving objects - the camera part is rebuilt in the shader) | none;
## WARMUP + FRAMES frames rendered while moving (defaults 30 + 10: the engine compiles its
## motion-vector pipelines in the background and draws NO velocity until they are ready - a
## short run shows the effect doing nothing - and TAA needs a few frames to settle), DT the simulated frame time (1/60 by default: a software frame takes
## seconds, so the effect is told the frame time the Mac would have), STRENGTH, SHUTTER,
## MAX_PX, THRESHOLD, SAMPLES the effect's knobs; DEBUG=1 paints the blur vectors instead
## (red / green = each pixel's x / y streak, blue = its tile neighbourhood's, all over the cap). With --gpu-profile, prints
## GPU_PROFILE_BEGIN/END round the last SAMPLES_GPU frames for tools/gpu_profile.py.
## Prints MB_FRAMES (frames the effect blurred) so a run that silently did nothing shows.

var _cam: Camera3D
var _pivot: Node3D
var _mover: Node3D
var _effect: MotionBlurEffect


func _initialize() -> void:
	var mode := _env("MODE", "forward")
	var root := Node3D.new()
	root.name = "MotionBlurShot"
	get_root().add_child(root)
	_build_world(root)
	_pivot = Node3D.new()
	root.add_child(_pivot)
	_pivot.position = Vector3(0.0, 1.6, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	_cam.near = 0.05
	_cam.far = 4000.0
	_pivot.add_child(_cam)
	# The spring arm's pose: 6.5 m behind and a little above the pivot, looking 15 degrees down.
	_pivot.rotation.x = deg_to_rad(-12.0)
	_cam.position = Vector3(0.0, 0.0, 6.5)
	var player := _player_proxy()
	root.add_child(player)
	player.position = Vector3(0.0, 0.0, 0.0)
	_cam.current = true
	if _env("MB", "1") != "0":
		_effect = MotionBlurEffect.new()
		_effect.strength = float(_env("STRENGTH", "1.0"))
		_effect.shutter = float(_env("SHUTTER", "0.5"))
		_effect.max_blur_px = float(_env("MAX_PX", "40"))
		_effect.threshold_px = float(_env("THRESHOLD", "3"))
		_effect.samples = int(_env("SAMPLES", "12"))
		_effect.debug_view = _env("DEBUG", "0") == "1"
		var compositor := Compositor.new()
		compositor.compositor_effects = [_effect]
		_cam.compositor = compositor
	var vp := get_root()
	match _env("AA", "taa"):
		"fsr":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.6
			vp.use_taa = false
		"none":
			vp.use_taa = false
		_:
			vp.use_taa = true
	var dt := float(_env("DT", str(1.0 / 60.0)))
	var speed := float(_env("SPEED", "45"))
	var rate := float(_env("RATE", "5"))
	# Godot compiles the motion-vector pipelines in the background the first time they are
	# needed, and draws without velocity until they are ready: warm up before judging anything.
	var frames := int(_env("WARMUP", "30")) + int(_env("FRAMES", "10"))
	var gpu_samples := int(_env("SAMPLES_GPU", "4"))
	var t := 0.0
	for i in frames:
		if i == frames - gpu_samples:
			print("GPU_PROFILE_BEGIN")
		t += dt
		match mode:
			"forward":
				_pivot.position = Vector3(0.0, 1.6, -speed * t)
				player.position = Vector3(0.0, 0.0, -speed * t)
			"strafe":
				_pivot.position = Vector3(speed * t, 1.6, 0.0)
				player.position = Vector3(speed * t, 0.0, 0.0)
				_pivot.rotation.y = deg_to_rad(90.0)
			"whip":
				_pivot.rotation.y = rate * t
			"object":
				_mover.position.x = -30.0 + speed * t
		if _effect:
			_effect.frame_seconds = dt
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_PROFILE_END")
	var img := vp.get_texture().get_image()
	var out := _env("OUT", "/tmp/motion_blur_shot.png")
	img.save_png(out)
	print("MB_FRAMES %d  mode=%s aa=%s mb=%s -> %s" % [_effect.frames_drawn if _effect else -1,
			mode, _env("AA", "taa"), _env("MB", "1"), out])
	quit()


func _build_world(root: Node3D) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.92)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	# A checker road 40 m wide and 3 km long: fine detail is what shows a streak.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 3000.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, 0.0, -1400.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _checker()
	gm.uv1_scale = Vector3(100.0, 750.0, 1.0)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = gm
	root.add_child(ground)
	# Columns down both kerbs every 8 m, alternating colours, and blocks behind them.
	var colors := [Color(0.85, 0.2, 0.15), Color(0.95, 0.95, 0.9), Color(0.15, 0.35, 0.8)]
	for k in 360:
		for side in [-1.0, 1.0]:
			var col := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 6.0, 1.0)
			col.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = colors[(k + int(side > 0.0)) % colors.size()]
			col.material_override = m
			col.position = Vector3(side * 14.0, 3.0, 30.0 - k * 8.0)
			root.add_child(col)
		if k % 3 == 0:
			for side in [-1.0, 1.0]:
				var blk := MeshInstance3D.new()
				var bb := BoxMesh.new()
				bb.size = Vector3(16.0, 20.0 + float((k * 7) % 30), 20.0)
				blk.mesh = bb
				var bm := StandardMaterial3D.new()
				bm.albedo_color = Color(0.55, 0.5, 0.45).lerp(Color(0.3, 0.35, 0.4), float(k % 5) / 4.0)
				blk.material_override = bm
				blk.position = Vector3(side * 30.0, bb.size.y * 0.5, 30.0 - k * 8.0)
				root.add_child(blk)
	# The crossing "car" for MODE=object.
	_mover = MeshInstance3D.new()
	var car := BoxMesh.new()
	car.size = Vector3(4.5, 1.5, 2.0)
	(_mover as MeshInstance3D).mesh = car
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.9, 0.75, 0.1)
	(_mover as MeshInstance3D).material_override = cm
	_mover.position = Vector3(-30.0, 0.75, -14.0)
	root.add_child(_mover)


func _player_proxy() -> Node3D:
	var body := Node3D.new()
	var capsule := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	capsule.mesh = cm
	capsule.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.12, 0.35)
	capsule.material_override = mat
	body.add_child(capsule)
	var gun := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.08, 0.12, 0.8)
	gun.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.05, 0.05)
	gun.material_override = gm
	gun.position = Vector3(0.35, 1.25, -0.4)
	body.add_child(gun)
	return body


func _checker() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var c := Color(0.2, 0.2, 0.22) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.75, 0.75, 0.7)
			if x % 32 == 0:
				c = Color(0.95, 0.85, 0.2)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
