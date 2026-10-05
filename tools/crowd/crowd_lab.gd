extends Node3D
## A bare lab for the crowd's locomotion (VISUAL_ROADMAP #28): real Pedestrians on a flat,
## gridded ground with nothing else in the world, so a stop, a turn, a head turning to a passing
## car or a crowd's cost can be looked at and measured on its own. A scene, not a SceneTree
## script, so the autoloads exist before Pedestrian compiles.
##
## Film a scenario (frames every STEP physics ticks, opengl3 under Xvfb):
##   MODE=film SCENARIO=turn OUT=/tmp/crowd LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s \
##     "-screen 0 960x540x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --resolution 960x540 tools/crowd/crowd_lab.tscn
## Measure the crowd's CPU per physics tick (headless is fine, nothing here renders):
##   MODE=bench N=100 godot --headless --path . tools/crowd/crowd_lab.tscn
##
## SCENARIO: dog (two dog walkers; FOLLOW=1 walks the camera beside the first), life (people talking, sitting, leaning, on the phone: CrowdLife), turn (walk, then an about-turn; side-on camera over a 0.5 m grid, so a sliding
## foot shows against the lines), look (people at the kerb as a car passes, the player walks
## by and a shot goes off), crowd (thirty people wandering a block's pavement), start (a
## standing person sets off and stops again). STEP (ticks between frames, default 12), FRAMES
## (default 30), MODEL (index into Pedestrian.MODELS for the lead, default 0).
## Bench: N people, the player DIST metres away (default: 0, 50, 100 and 200 in turn: every
## LOD tier), TICKS measured after WARM ticks.

var _mode := "film"
var _scenario := "turn"
var _ground: StaticBody3D
var _player: Node3D
var _car: Node3D
var _peds: Array = []
var _props_rows: Array = []
var _dog_legs: Array = []
var _tick: int = 0
var _tail: Node


func _physics_process(_delta: float) -> void:
	if _tail:
		_tail.t0 = Time.get_ticks_usec()


func _ready() -> void:
	_mode = _env("MODE", "film")
	_scenario = _env("SCENARIO", "turn")
	Engine.max_physics_steps_per_frame = 1
	process_physics_priority = -100000
	_tail = (load("res://tools/crowd/tick_tail.gd") as GDScript).new()
	_tail.process_physics_priority = 100000
	add_child(_tail)
	_build_world()
	await get_tree().process_frame
	if _mode == "bench":
		await _bench()
	elif _mode == "skate":
		await _skate()
	else:
		await _film()
	get_tree().quit()


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return fallback if v == "" else v


func _build_world() -> void:
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	_ground.add_child(shape)
	add_child(_ground)
	_player = Node3D.new()
	_player.add_to_group("player")
	_player.position = Vector3(0.0, 0.0, 30.0)
	add_child(_player)
	if _mode == "bench":
		return
	# The player, as the orange capsule the game falls back to.
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	body.mesh = capsule
	body.position.y = 0.9
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.45, 0.1)
	body.material_override = orange
	_player.add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	mesh.mesh = plane
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var line := x % 32 < 1 or y % 32 < 1
			var c := 0.08 if line else (0.24 if ((x / 32) + (y / 32)) % 2 == 0 else 0.20)
			img.set_pixel(x, y, Color(c, c, c * 1.02))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(120.0, 120.0, 1.0) # one texture = 1 m: 0.5 m squares
	mat.roughness = 0.9
	mesh.material_override = mat
	add_child(mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.67, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.84)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)


## One pedestrian on a pavement ring round `rect`, standing at `at`.
func _spawn(rect: Rect2, at: Vector2, seed_value: int, model: int = -1) -> Pedestrian:
	var p := Pedestrian.new()
	p.setup(rect, 4.0, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.position = Vector3(at.x, 0.1, at.y)
	if model >= 0:
		# Pick the model the style roll would: re-seed the cosmetic stream until it lands on it.
		var s := seed_value
		while true:
			var r := RandomNumberGenerator.new()
			r.seed = hash([s, "style"])
			if r.randi() % Pedestrian.MODELS.size() == model:
				break
			s += 1
		p.setup(rect, 4.0, s)
		p.pause_chance = 0.0
		p.cross_chance = 0.0
	add_child(p)
	_peds.append(p)
	return p


## Holds a walker on a leg: `_target` is set every tick (the lab steers, not the ring).
func _steer(p: Pedestrian, target: Vector2) -> void:
	p.set("_target", target)
	p.set("_route", PackedVector2Array())
	p.set("_route_pending", false)


func _camera(pos: Vector3, look: Vector3, fov: float = 40.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	add_child(cam)
	# CAM=x,y,z and LOOK=x,y,z override any scenario's camera (FOV too).
	if OS.get_environment("CAM") != "":
		var c := OS.get_environment("CAM").split_floats(",")
		pos = Vector3(c[0], c[1], c[2])
	if OS.get_environment("LOOK") != "":
		var l := OS.get_environment("LOOK").split_floats(",")
		look = Vector3(l[0], l[1], l[2])
	if OS.get_environment("FOV") != "":
		cam.fov = float(OS.get_environment("FOV"))
	cam.position = pos
	cam.look_at(look, Vector3.UP)
	cam.current = true


func _film() -> void:
	var out := _env("OUT", "crowd_lab")
	DirAccess.make_dir_recursive_absolute(out)
	var step := int(_env("STEP", "12"))
	var frames := int(_env("FRAMES", "30"))
	var model := int(_env("MODEL", "0"))
	var rect := Rect2(-30.0, -1.5, 60.0, 40.0) # pavement band along z = 0 (the ring's north side)
	var lead: Pedestrian
	var legs: Array = []
	match _scenario:
		"turn":
			lead = _spawn(rect, Vector2(-5.0, 0.0), 11, model)
			legs = [Vector2(2.0, 0.0), Vector2(-6.0, 0.0)]
			_camera(Vector3(-2.0, 1.0, 6.5), Vector3(-2.0, 0.8, 0.0), 44.0)
		"start":
			lead = _spawn(rect, Vector2(-3.0, 0.0), 11, model)
			lead.set("_pause_left", 1.0)
			legs = [Vector2(3.0, 0.0)]
			_camera(Vector3(0.0, 1.1, 7.0), Vector3(0.0, 0.8, 0.0), 42.0)
		"look":
			for i in 3:
				var p := _spawn(rect, Vector2(-1.6 + 1.6 * i, 0.0), 21 + i * 7, (model + i * 3) % Pedestrian.MODELS.size())
				p.set("_pause_left", 1000.0)
				(p.get("_visual") as Node3D).rotation.y = PI # facing the road, and the camera
				p.call("_play_idle")
				p.set("_speed", 0.0)
			_car = MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(4.4, 1.4, 1.9)
			_car.mesh = box
			_car.position = Vector3(-22.0, 0.7, 4.2)
			_car.add_to_group("vehicle")
			add_child(_car)
			_player.position = Vector3(14.0, 0.0, 9.0)
			_camera(Vector3(0.0, 2.6, 7.5), Vector3(0.0, 1.2, 0.0), 34.0)
		"props":
			# One person per carry, standing in a row facing the camera (WALK=1: walking at it).
			var kinds := [CrowdLife.Carry.CALL, CrowdLife.Carry.TEXT, CrowdLife.Carry.CUP, CrowdLife.Carry.BAG, CrowdLife.Carry.SMOKE]
			for i in kinds.size():
				var p := _spawn(rect, Vector2(-2.4 + 1.2 * i, 0.0), 70 + i * 5, (model + i * 2) % Pedestrian.MODELS.size())
				p.life_spawn_chance = 0.0
				_props_rows.append([p, kinds[i]])
			_player.position = Vector3(0.0, 0.0, -10.0)
			_camera(Vector3(0.0, 1.4, -4.2), Vector3(0.0, 1.0, 0.0), 40.0)
		"dog":
			# Two people walking dogs along the pavement toward the camera's side view.
			for i in 2:
				var p := Pedestrian.new()
				p.setup(rect, 4.0, 90 + i * 17)
				p.jogger_share = Vector2.ZERO
				p.dog_share = Vector2.ONE
				p.life_spawn_chance = 0.0
				p.pause_chance = 0.0
				p.cross_chance = 0.0
				p.position = Vector3(-6.0 - 3.0 * i, 0.0, 0.3 + 0.8 * i)
				add_child(p)
				_peds.append(p)
				_dog_legs.append(p)
			_player.position = Vector3(0.0, 0.0, -8.0)
			_camera(Vector3(0.0, 1.3, -5.5), Vector3(0.0, 0.6, 0.5), 50.0)
		"life":
			_stage_life(rect)
			_camera(Vector3(0.0, 2.2, -9.0), Vector3(0.0, 1.0, 1.5), 50.0)
		"crowd":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var r := Rect2(-12.0, -12.0, 24.0, 24.0)
			for i in 30:
				var p := Pedestrian.new()
				p.setup(r, 4.0, 1000 + i)
				p.position = Vector3(rng.randf_range(-11.0, 11.0), 0.1, -11.0 + rng.randf_range(0.5, 3.0))
				add_child(p)
				_peds.append(p)
			_camera(Vector3(0.0, 7.0, 5.0), Vector3(0.0, 0.5, -10.0), 50.0)
	# Everyone faces the way they will walk from the first frame.
	for i in 6:
		await get_tree().physics_frame
	for row: Array in _props_rows:
		var p: Pedestrian = row[0]
		p._carry = row[1]
		if OS.get_environment("WALK") == "1":
			p.set("_visual", p._visual)
		else:
			p._visual.rotation.y = 0.0
			p._start_stand(1000.0)
			if row[1] == CrowdLife.Carry.SMOKE:
				p._act = CrowdLife.Act.LEAN
	var leg := 0
	for f in frames:
		for t in step:
			if lead and leg < legs.size():
				_steer(lead, legs[leg])
				var here := Vector2(lead.position.x, lead.position.z)
				if here.distance_to(legs[leg]) < 1.2 and leg + 1 < legs.size():
					leg += 1
			for p: Pedestrian in _dog_legs:
				_steer(p, Vector2(30.0, p.position.z))
			if _scenario == "dog" and OS.get_environment("FOLLOW") == "1" and not _dog_legs.is_empty():
				# A camera walking alongside the first walker, at the dog's side (FOLLOW=1).
				var w: Pedestrian = _dog_legs[0]
				_camera(w.position + Vector3(0.6, 1.05, -3.4), w.position + Vector3(0.4, 0.55, -0.6), 38.0)
			if _scenario == "look":
				_stage_look(_tick)
				if OS.get_environment("DEBUG") == "1" and _tick % 30 == 0:
					var line := "tick %d:" % _tick
					for p in _peds:
						line += " [yaw %.0f pitch %.0f near %s pt %s]" % [rad_to_deg(p.get("_look_yaw")), rad_to_deg(p.get("_look_pitch")), p.get("_look_near"), p.get("_look_point")]
					print(line)
			await get_tree().physics_frame
			_tick += 1
		if DisplayServer.get_name() == "headless":
			continue # no frames to grab: the DEBUG lines are the output
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f%03d.png" % [out, f])
	print("crowd_lab: %d frames to %s" % [frames, out])


## The life scenario (CrowdLife): a pavement along z = 0 with a shop wall behind it (the ring's
## inside is +z) and a bench against the wall, and N people (default 8, LIFE_SEED) who all start
## doing something at once (life_spawn_chance 1): talking, on the phone, sitting, leaning,
## looking in the window. The camera looks at the wall from the road. TIME_SCALE to fast-forward.
func _stage_life(rect: Rect2) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(40.0, 4.0, 1.0)
	ws.shape = wb
	wall.add_child(ws)
	var wm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = wb.size
	wm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	wm.material_override = mat
	wall.add_child(wm)
	wall.position = Vector3(0.0, 2.0, 3.5)
	add_child(wall)
	for bx in [-4.0, 5.0]:
		var bench := MeshInstance3D.new()
		bench.mesh = PropFactory.model_bench()
		bench.position = Vector3(bx, 0.0, 2.4)
		add_child(bench)
		CrowdLife.add_seat(self, bench.position, 0.0, null)
	var n := int(_env("N", "8"))
	var seed0 := int(_env("LIFE_SEED", "40"))
	for i in n:
		var p := Pedestrian.new()
		p.setup(rect, 4.0, seed0 + i * 13)
		p.life_spawn_chance = 1.0
		p.position = Vector3(-7.0 + 14.0 * float(i) / maxf(n - 1, 1), 0.0, 0.6)
		add_child(p)
		_peds.append(p)
	_player.position = Vector3(0.0, 0.0, -12.0)
	Engine.time_scale = float(_env("TIME_SCALE", "1"))
	if _env("DBG", "") != "":
		add_child(load(_env("DBG", "")).new())


## The look scenario's events, by tick: a car passes close (ticks 0-260), the player walks by
## (270-500), a shot off to the right (560).
func _stage_look(tick: int) -> void:
	var dt := 1.0 / 60.0
	if tick < 260:
		_car.position.x += 10.0 * dt
	else:
		_car.position = Vector3(-200.0, 0.7, 4.2)
	if tick == 260:
		_player.position = Vector3(7.0, 0.0, 2.6)
	if tick >= 270 and tick < 500:
		_player.position = Vector3(7.0 - float(tick - 270) * dt * 3.2, 0.0, 2.6)
	if tick == 500:
		_player.position = Vector3(-14.0, 0.0, 9.0)
	if tick == 560:
		Pedestrian.alarm(get_tree(), Vector3(9.0, 1.0, 3.0), 30.0, 0, false, "")


## Foot skate: people walking a long straight leg at their own pace; each tick, the lower of
## the two toes, when it is within 2 cm of the ground, should not move. Prints how fast planted
## feet slide (m/s) against how fast the body goes. Headless is fine (bone poses are CPU).
##   MODE=skate godot --headless --path . tools/crowd/crowd_lab.tscn
func _skate() -> void:
	var rect := Rect2(-300.0, -1.5, 600.0, 40.0)
	var total_slide := 0.0
	var total_body := 0.0
	for m in Pedestrian.MODELS.size():
		var p := _spawn(rect, Vector2(-150.0, 0.0), 300 + m * 11, m)
		p.physics_range = 1000.0 # stride 1, the near path
		_steer(p, Vector2(250.0, 0.0))
		for i in 90:
			_steer(p, Vector2(250.0, 0.0))
			await get_tree().physics_frame
		var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
		var toes := [skel.find_bone("LeftToeBase"), skel.find_bone("RightToeBase")]
		var samples: Array = [] # per tick: [left, right]
		var start := p.global_position
		var ticks := 300
		for i in ticks:
			_steer(p, Vector2(250.0, 0.0))
			await get_tree().physics_frame
			var now: Array = []
			for b in toes:
				now.append(skel.global_transform * skel.get_bone_global_pose(b).origin)
			samples.append(now)
		var floor_y := INF
		for now: Array in samples:
			floor_y = minf(floor_y, minf((now[0] as Vector3).y, (now[1] as Vector3).y))
		var slide := 0.0
		var planted := 0
		for i in range(1, samples.size()):
			for f in 2:
				var a: Vector3 = samples[i - 1][f]
				var b2: Vector3 = samples[i][f]
				if a.y < floor_y + 0.02 and b2.y < floor_y + 0.02:
					slide += Vector2(b2.x - a.x, b2.z - a.z).length()
					planted += 1
		var body := p.global_position.distance_to(start) / (ticks / 60.0)
		var sl := slide / maxf(planted / 60.0, 0.001)
		total_slide += sl
		total_body += body
		print("crowd_lab skate: %s body %.2f m/s, planted foot slides %.2f m/s (%d%% of ticks planted)"
			% [Pedestrian.MODELS[m].get_file(), body, sl, planted * 100 / ticks])
		p.queue_free()
		_peds.clear()
	var n := float(Pedestrian.MODELS.size())
	print("crowd_lab skate: mean body %.2f m/s, planted foot slide %.2f m/s" % [total_body / n, total_slide / n])


func _bench() -> void:
	var n := int(_env("N", "100"))
	var warm := int(_env("WARM", "90"))
	var ticks := int(_env("TICKS", "300"))
	var dists: Array = [0.0, 50.0, 100.0, 200.0]
	if OS.get_environment("DIST") != "":
		dists = [float(OS.get_environment("DIST"))]
	# The same people for every distance: a 24 m block, everyone on its pavement.
	var rect := Rect2(-12.0, -12.0, 24.0, 24.0)
	var base := await _measure(warm, ticks)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var p := Pedestrian.new()
		p.setup(rect, 4.0, 5000 + i)
		var a := rng.randf() * TAU
		p.position = Vector3(cos(a) * 10.0, 0.1, sin(a) * 10.0)
		add_child(p)
		_peds.append(p)
	if OS.get_environment("LOOK_RANGE") != "":
		for p in _peds:
			p.set("look_range", float(OS.get_environment("LOOK_RANGE")))
	if OS.get_environment("HIDE") == "1":
		for p in _peds:
			(p.get("_visual") as Node3D).visible = false
	if OS.get_environment("STILL") == "1":
		for p in _peds:
			p.set("_pause_left", 100000.0)
	if OS.get_environment("ANIM_OFF") == "1":
		for p in _peds:
			(p as Node).set("_anim", null)
	if OS.get_environment("SCRIPTS_OFF") == "1":
		for p in _peds:
			(p as Node).set_physics_process(false)
	for d in dists:
		_player.position = Vector3(float(d), 0.0, 0.0)
		var ms := await _measure(warm, ticks)
		var strides := {}
		for p in _peds:
			var k := int(p.get("_lod_stride"))
			strides[k] = int(strides.get(k, 0)) + 1
		print("crowd_lab bench: %d people, player %3d m away: %.3f ms a physics tick (%.3f per 100 over an empty scene of %.3f) strides %s"
			% [n, int(d), ms, (ms - base) * 100.0 / n, base, strides])


## Mean time the nodes spend in a physics tick (ms: every _physics_process, the animation
## they advance and their move_and_slide), over `ticks` after `warm`. Not the Performance
## monitor: TIME_PHYSICS_PROCESS is the worst tick of the last second, not the mean.
func _measure(warm: int, ticks: int) -> float:
	for i in warm:
		await get_tree().physics_frame
	_tail.total_usec = 0
	_tail.ticks = 0
	for i in ticks:
		await get_tree().physics_frame
	return float(_tail.total_usec) / 1000.0 / maxf(float(_tail.ticks), 1.0)
