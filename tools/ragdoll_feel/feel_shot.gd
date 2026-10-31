extends Node
## Ragdoll feel (RagdollFeel), frame by frame in a small street: a walker shot from the front /
## behind / the side / in the head (the stagger), flung hard (limbs trailing), hit by a moving car
## (over the bonnet) or knocked at the top of a flight of steps (rolling down). opengl3, seconds:
##
##   SCENE=car OUT=build/ragdoll_feel/car LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     tools/ragdoll_feel/feel_shot.tscn --resolution 1280x720
##
## Env: SCENE=shot_front|shot_back|shot_side|shot_head|fly|car|stairs, OUT (prefix, _NN.png),
## FRAMES (physics steps, comma list), CAM / LOOK (x,y,z), FOLLOW=1 (the camera keeps CAM - LOOK
## from the pelvis), NOSHOT=1 (only the TRACE lines: pelvis,
## head and chest heights and the worst joint gap every 6 steps), RAGDOLL_FEEL=0 the before.

func _ready() -> void:
	call_deferred("_run")


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	var out := _env("OUT", "build/ragdoll_feel/shot")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out.get_base_dir()))
	var scene := _env("SCENE", "shot_front")
	var noshot := _env("NOSHOT", "") == "1"
	# Debris lives by the wall clock, which a software render eats: keep the doll for the stills.
	get_node("/root/PhysicsBudget").set("debris_lifetime", 600.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)
	_slab(Vector3(0, -0.5, 0), Vector3(80, 1, 80), PropFactory.road("asphalt", 4.0, Color(0.85, 0.85, 0.85), 7))
	var start := Vector3(0.0, 0.02, 0.0)
	var cam_at := "-5.5,1.7,4.5"
	var look := "0,0.9,0"
	var defaults := "0,12,24,36,48,72,110,200"
	var car: Vehicle = null
	if scene == "stairs":
		# Ten steps of 0.17 m on 0.30 m, falling toward +z, a landing at the top.
		var mat := PropFactory.road("sidewalk", 3.0, Color(0.95, 0.95, 0.92), 8, 1.5, 0.4)
		for i in 10:
			var h := 1.7 - 0.17 * float(i)
			_slab(Vector3(0, h * 0.5, -0.15 + 0.3 * float(i) + (0.0 if i > 0 else -1.0)), Vector3(4.0, h, 0.3 if i > 0 else 2.3), mat)
		start = Vector3(0.0, 1.72, -1.2)
		cam_at = "-6.0,3.2,1.5"
		look = "0,0.9,1.4"
		defaults = "0,20,40,60,90,130,180,260"
	elif scene == "car":
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		car = Vehicle.random_car(rng)
		add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(7.5, 0.8, 0.0))
		cam_at = "-6.0,2.6,8.5"
		look = "-6.0,0.8,0"
		defaults = "22,27,32,38,46,58,76,130"
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.global_position = _v3(_env("CAM", cam_at))
	cam.look_at(_v3(_env("LOOK", look)))
	cam.current = true
	var frames := Array(_env("FRAMES", defaults).split(",")).map(func(x): return int(x))
	for i in 30:
		await get_tree().physics_frame
	var p := Pedestrian.new()
	p.setup(Rect2(-20, -20, 40, 40), 4.0, int(_env("SEED", "4242")))
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_chance = 0.0
	p.life_spawn_chance = 0.0
	add_child(p)
	p.global_position = start
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Standing still where it was put (a walking walker would wander off the mark).
	p.set_physics_process(false)
	# The walker faces wherever it was walking; turn the visual to face the camera's left (-x).
	if p.get("_visual") is Node3D:
		(p.get("_visual") as Node3D).rotation.y = -PI * 0.5 if scene != "stairs" else 0.0
	var rifle := Vector3(14.0, 5.0, 0.0)
	match scene:
		"shot_front":
			# Shot from in front (-x): the round travels +x.
			p.shot(start + Vector3(0, 1.3, 0), Vector3.RIGHT, Vector3.RIGHT * 14.0 + Vector3.UP * 5.0)
		"shot_back":
			p.shot(start + Vector3(0, 1.3, 0), Vector3.LEFT, Vector3.LEFT * 14.0 + Vector3.UP * 5.0)
		"shot_side":
			p.shot(start + Vector3(0.0, 1.25, 0.12), Vector3.BACK, Vector3.BACK * 14.0 + Vector3.UP * 5.0)
		"shot_head":
			p.shot(start + Vector3(0, 1.62, 0), Vector3.RIGHT, rifle)
		"fly":
			p.knock(Vector3(9.0, 9.0, 0.0))
		"stairs":
			p.knock(Vector3(0.0, 1.5, 2.2))
		"car":
			car.linear_velocity = Vector3(-14.0, 0.0, 0.0)
	var doll: Ragdoll = null
	var step := 0
	var n := 0
	var last: int = frames.max()
	var worst := 0.0
	var follow := _env("FOLLOW", "") == "1"
	var offset := cam.global_position - _v3(_env("LOOK", look))
	while step <= last:
		if follow and doll != null and is_instance_valid(doll) and not doll.bodies.is_empty():
			var at := doll._pelvis()
			cam.global_position = cam.global_position.lerp(at + offset, 0.25)
			cam.look_at(at + Vector3.UP * 0.2)
		if car != null and is_instance_valid(car):
			# 14 m/s into the walker, then the driver stands on the brakes (0.75 g).
			var vx := -14.0 if step < 36 else minf(car.linear_velocity.x + 7.4 / 60.0, 0.0)
			car.linear_velocity = Vector3(vx, car.linear_velocity.y, car.linear_velocity.z)
		if doll == null:
			for c in get_children():
				if c is Ragdoll:
					doll = c
		if doll != null and doll._joints != null and not doll._joints.frozen:
			worst = maxf(worst, doll._joints.gap())
		if step % 6 == 0 and doll != null and doll._joints != null:
			var j := doll._joints
			var pv := (j.parts.get("pelvis") as Node3D).global_position
			var hd := j.parts.get("head") as Node3D
			var cx := car.global_position.x if car != null and is_instance_valid(car) else 0.0
			print("TRACE %d pelvis %.2f,%.2f,%.2f head_y %.2f frozen %s gap %.3f car_x %.2f roll %.2f v %.2f" % [step, pv.x, pv.y, pv.z, hd.global_position.y if hd else -1.0, j.frozen, worst, cx, j.feel.rolling if j.feel else -1.0, (j.parts.get("pelvis") as RigidBody3D).linear_velocity.length()])
		if not noshot and step in frames:
			await get_tree().process_frame
			await get_tree().process_frame
			var path := ProjectSettings.globalize_path("res://").path_join("%s_%02d.png" % [out, n])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path, " step ", step)
			n += 1
		await get_tree().physics_frame
		step += 1
	print("WORST GAP %.3f staggered %d car %d" % [worst, RagdollFeel.staggered, RagdollFeel.car_wraps])
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
