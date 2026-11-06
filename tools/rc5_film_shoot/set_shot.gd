extends Node
## The film set at night ALONE (no city): the shoot's real kit meshes (HMIs, balloon, track and
## dolly, flags, bounces, video village, a trailer) laid out by FilmShoot.layout() on a flat street,
## lit by the city scene's WorldEnvironment with the lamps on, FilmShootBuild's lights and
## FilmShootNight's dress. Small enough for lavapipe (Forward+, the Mac's renderer), where one
## city chunk is not:
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json OUT=/tmp/set.png xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 --audio-driver \
##     Dummy --path . res://tools/rc5_film_shoot/set_shot.tscn --resolution 960x540
##
## (opengl3: --rendering-driver opengl3, LIBGL_ALWAYS_SOFTWARE=1.) EYE=x,y,z,yaw,pitch (TRUE world,
## y over the street; default the set from 28 m up the street), FOV (default 55), FRAMES (default
## 60), FILM_SHOOT_NIGHT=0 the before.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	var env_node: Node = city.get_node_or_null("WorldEnvironment")
	if env_node:
		city.remove_child(env_node)
		env_node.owner = null
		add_child(env_node)
	city.free()
	var we := env_node as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.012, 0.016, 0.03)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.05, 0.06, 0.09)
		env.ambient_light_energy = 0.5
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	DayNight.lamp_now = 1.0
	var m := FilmShoot.decide(plan, Vector2i(0, -1))
	var lay := FilmShoot.layout(m)
	# A chunk with no relief (its plan has no macro): FilmShootNight needs ground_y / _gy / a parent.
	var ch := CityChunk.new()
	var flat := CityPlan.new()
	ch.plan = flat
	ch.market_road = m.rect
	add_child(ch)
	# The street: road between the kerbs, pavements and a wall either side.
	var half := float(m.width) * 0.5
	var mid := (float(m.lo) + float(m.hi)) * 0.5
	var length := float(m.hi) - float(m.lo)
	for spec: Array in [[0.0, float(m.width), CityChunk.ROAD_TOP, Color(0.09, 0.09, 0.09)],
			[-(half + 2.5), 5.0, CityChunk.SIDEWALK_TOP, Color(0.32, 0.31, 0.29)], [half + 2.5, 5.0, CityChunk.SIDEWALK_TOP, Color(0.32, 0.31, 0.29)],
			[-(half + 5.5), 1.0, 9.0, Color(0.42, 0.38, 0.33)], [half + 5.5, 1.0, 9.0, Color(0.42, 0.38, 0.33)]]:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var p := FilmShoot.point(m, mid, float(spec[0]))
		var across: Vector2 = FilmShoot.dirs(m)[1]
		var along: Vector2 = FilmShoot.dirs(m)[0]
		var size := Vector3(absf(across.x) * float(spec[1]) + absf(along.x) * length, float(spec[2]), absf(across.y) * float(spec[1]) + absf(along.y) * length)
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[3]
		mat.roughness = 0.85
		bm.material = mat
		box.mesh = bm
		box.position = Vector3(p.x, float(spec[2]) * 0.5, p.y)
		ch.add_child(box)
	var add := func(mesh: Mesh, xf: Transform3D) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = xf
		ch.add_child(mi)
	var ss := -float(m.camp_side)
	var tr: Dictionary = lay.track
	var tmid := (float(tr.t0) + float(tr.t1)) * 0.5
	add.call(FilmShootKit.track(FilmShoot.TRACK_LEN), FilmShootBuild.xf_at(m, tmid, float(tr.o), Vector2(0, 1)))
	add.call(FilmShootKit.dolly(), FilmShootBuild.xf_at(m, float(lay.dolly_t), float(tr.o), Vector2(0, ss)) * Transform3D(Basis(), Vector3(0, 0.1, 0)))
	for h: Dictionary in lay.hmis:
		add.call(FilmShootKit.hmi(), FilmShootBuild.xf_at(m, float(h.t), float(h.o), h.aim))
	var bl: Dictionary = lay.balloon
	add.call(FilmShootKit.balloon(), FilmShootBuild.xf_at(m, float(bl.t), float(bl.o), Vector2(1, 0)))
	for f: Dictionary in lay.flags:
		add.call(FilmShootKit.c_stand(false), FilmShootBuild.xf_at(m, float(f.t), float(f.o), f.aim))
	for f: Dictionary in lay.bounces:
		add.call(FilmShootKit.c_stand(true), FilmShootBuild.xf_at(m, float(f.t), float(f.o), f.aim))
	var vl: Dictionary = lay.village
	add.call(FilmShootKit.village(), FilmShootBuild.xf_at(m, float(vl.t), float(vl.o), Vector2(0, -float(m.camp_side))))
	var cr: Dictionary = lay.crane
	add.call(FilmShootKit.crane(), FilmShootBuild.xf_at(m, float(cr.t), float(cr.o), Vector2(0, ss)))
	FilmShootBuild._lights(ch, m, lay)
	for l in ch.get_children():
		if l is OmniLight3D:
			(l as OmniLight3D).light_energy = 2.6 * float(l.get_meta("lamp_gain", 1.0)) if FilmShootNight.enabled else 2.6
			(l as OmniLight3D).visible = true
	FilmShootNight.dress(ch, m, lay)
	for l in ch.get_children():
		if l is OmniLight3D:
			(l as OmniLight3D).light_energy = 2.6 * float(l.get_meta("lamp_gain", 1.0))
	var cam := Camera3D.new()
	var eye := OS.get_environment("EYE")
	if eye == "":
		eye = "1488.5,1.7,-1127,6,1"
	var e := eye.split(",")
	cam.position = Vector3(e[0].to_float(), e[1].to_float(), e[2].to_float())
	cam.rotation_degrees = Vector3(e[4].to_float(), e[3].to_float(), 0.0)
	cam.fov = OS.get_environment("FOV").to_float() if OS.get_environment("FOV") != "" else 55.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	var frames := OS.get_environment("FRAMES").to_int() if OS.get_environment("FRAMES") != "" else 60
	for i in frames:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/set.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("SET_SHOT saved ", out)
	get_tree().quit()
