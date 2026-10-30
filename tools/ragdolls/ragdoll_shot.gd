extends Node
## Stills of a ragdoll falling, frame by frame, in a small street (asphalt, a kerb and a
## pavement, a parked car): a walker is hit toward the car and falls against it. The same frames
## with RAGDOLLS=0 are the old single tumbling body (the before). opengl3, seconds:
##
##   OUT=build/ragdolls/after LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     tools/ragdolls/ragdoll_shot.tscn --resolution 1280x720
##
## Env: OUT (file prefix; _NN.png per frame), FRAMES (physics steps to shoot at, comma list),
## SCENE=car|kerb|blast (into a parked car / off the kerb into the road / a blast with gibs),
## MODEL (index into Pedestrian.MODELS), CAM=x,y,z and LOOK=x,y,z.

func _ready() -> void:
	call_deferred("_run")


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	var out := _env("OUT", "build/ragdolls/shot")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out.get_base_dir()))
	var frames := Array(_env("FRAMES", "0,10,20,32,48,80,140,300").split(",")).map(func(x): return int(x))
	var scene := _env("SCENE", "car")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# The road, the kerb and the pavement.
	_slab(Vector3(0, -0.5, 0), Vector3(60, 1, 60), PropFactory.road("asphalt", 4.0, Color(0.85, 0.85, 0.85), 7))
	_slab(Vector3(0, 0.075, -6.0), Vector3(60, 0.15, 5.0), PropFactory.road("sidewalk", 3.0, Color(0.95, 0.95, 0.92), 8, 1.5, 0.4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if scene != "kerb":
		var car := Vehicle.random_car(rng)
		add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.6, 0.6))
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.global_position = _v3(_env("CAM", "-6.5,2.4,6.5"))
	cam.look_at(_v3(_env("LOOK", "0,0.6,-0.6")))
	cam.current = true
	for i in 30:
		await get_tree().physics_frame
	var models: Array = load("res://scripts/npc/pedestrian.gd").MODELS
	var p := Pedestrian.new()
	var start := Vector3(0.0, 0.16, -4.6)
	if scene == "kerb":
		start = Vector3(0.0, 0.16, -4.0)
	p.setup(Rect2(-20, -9, 40, 6), 4.0, 4242)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_chance = 0.0
	p.life_spawn_chance = 0.0
	add_child(p)
	p.global_position = start
	await get_tree().physics_frame
	await get_tree().physics_frame
	var impulse := Vector3(0.0, 4.0, 7.0)
	var gibs := 0
	match scene:
		"kerb":
			impulse = Vector3(1.0, 2.5, 3.2)
		"blast":
			impulse = Vector3(3.0, 9.0, 6.0)
			gibs = 2
	p.knock(impulse, gibs)
	var step := 0
	var n := 0
	for f: int in frames:
		while step < f:
			await get_tree().physics_frame
			step += 1
		await get_tree().process_frame
		await get_tree().process_frame
		var path := ProjectSettings.globalize_path("res://").path_join("%s_%02d.png" % [out, n])
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path, " step ", step)
		n += 1
	get_tree().quit()


func _slab(at: Vector3, size: Vector3, mat: Material) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	add_child(b)
	b.global_position = at
