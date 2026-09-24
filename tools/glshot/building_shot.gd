extends SceneTree
## Renders one generated Building with the real OpenGL renderer (no browser, no web export) and
## saves a PNG. Runs under a virtual display with Mesa's llvmpipe, so it works in a container:
##
##   OUT=shot.png FINISH=3 BSEED=7 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/building_shot.gd --resolution 960x540
##
## Env: OUT (png path), BSEED (building seed), FINISH (Building.Finish index), LOT (meters),
## HMIN / HMAX (height range), KIT=0 (no facade kit), CAM_POS / CAM_LOOK / CAM_FOV (an exact
## close-up; see below). This is the Compatibility renderer, like the web build: lighting is
## flat, judge geometry and materials. ~20 s per shot on llvmpipe.
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.7, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3d.add_child(sun)
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	# KIT=0 renders the building without the facade kit, for a before / after of the same seed.
	if OS.get_environment("KIT") == "0":
		Building.kit_enabled = false
	var b := scene.instantiate()
	b.seed = _env_int("BSEED", 7)
	var lot := float(_env_int("LOT", 30))
	b.lot_size = Vector2(lot, lot)
	b.min_height = float(_env_int("HMIN", 60))
	b.max_height = float(_env_int("HMAX", 90))
	var fin := OS.get_environment("FINISH")
	if fin != "":
		b.finish_options.assign([int(fin)])
	root3d.add_child(b)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var h: float = b.height
	# CAM_DIST / CAM_EYE / CAM_TGT frame a close-up (metres): distance out from the corner, eye
	# height, and the height it looks at. Without them the whole building is framed, which is
	# useless for judging facade detail.
	var dist := float(_env_int("CAM_DIST", 0))
	# CAM_POS=x,y,z and CAM_LOOK=x,y,z (metres, building space) place the camera exactly, for a
	# close look at one window, cornice corner or balcony.
	var pos_s := OS.get_environment("CAM_POS")
	if pos_s != "":
		var p := pos_s.split_floats(",")
		var l := OS.get_environment("CAM_LOOK").split_floats(",")
		if l.size() < 3:
			l = PackedFloat64Array([0.0, p[1], 0.0])
		cam.look_at_from_position(Vector3(p[0], p[1], p[2]), Vector3(l[0], l[1], l[2]))
		if OS.get_environment("CAM_FOV") != "":
			cam.fov = OS.get_environment("CAM_FOV").to_float()
	elif dist > 0.0:
		var eye := float(_env_int("CAM_EYE", 6))
		var tgt := float(_env_int("CAM_TGT", 10))
		cam.look_at_from_position(Vector3(dist * 0.45, eye, dist), Vector3(0, tgt, 0))
	else:
		cam.look_at_from_position(Vector3(lot * 2.0, h * 0.9, lot * 3.0), Vector3(0, h * 0.45, 0))
	cam.far = 2000.0
	cam.current = true
	for i in 10:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "building_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out, " finish=", b.finish, " style=", b.window_style, " height=", b.height, " footprint=", b.footprint)
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
