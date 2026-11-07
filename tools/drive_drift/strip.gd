extends Node
## Stills of a drift on a flat asphalt slab under a sun (opengl3, Xvfb, --fixed-fps 60 so a frame
## is 1/60 s of game time): the same scripted inputs as the probe's drift_r (80 km/h, handbrake and
## right lock half a second, throttle with the stick centred 1.5 s, counter-steer 1 s), shot from a
## chase camera every SHOT_EVERY frames, then the skid marks from above.
##   OUT_DIR=build/drift PREFIX=after_ TYPE=3 SCEN=drift xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . --fixed-fps 60 \
##     --resolution 1280x720 tools/drive_drift/strip.tscn
## SCEN=drift|u180|jturn|power. DRIVE_DRIFT=0 is the before.

var car: Vehicle
var cam: Camera3D
var dummy: Node3D
var out_dir := OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "build/drift"
var prefix := OS.get_environment("PREFIX")
var shot_every := int(OS.get_environment("SHOT_EVERY")) if OS.get_environment("SHOT_EVERY") != "" else 20
var frame := 0
var n := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200, 2, 1200)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	mi.mesh = pm
	mi.material_override = PropFactory.road("asphalt", 6.0, Color(0.55, 0.55, 0.56), 7)
	ground.add_child(mi)
	# Lane lines so the motion reads.
	for i in range(-30, 31):
		var d := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 0.02, 3.0)
		d.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.9, 0.85)
		d.material_override = m
		d.position = Vector3(-6.0, 0.01, i * 10.0)
		ground.add_child(d)
	add_child(ground)
	dummy = Node3D.new()
	add_child(dummy)
	cam = Camera3D.new()
	cam.fov = 60
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/%s%s_%02d.jpg" % [out_dir, prefix, tag, n], 0.88)
	n += 1


func _chase() -> void:
	var v := car.linear_velocity
	v.y = 0.0
	var dir := v.normalized() if v.length() > 2.0 else -car.global_basis.z
	var p := car.global_position
	var want := p - dir * 11.0 + Vector3.UP * 4.0
	cam.global_position = cam.global_position.lerp(want, 0.15) if frame > 0 else want
	cam.look_at(p + Vector3.UP * 0.8, Vector3.UP)


func _tick() -> void:
	await get_tree().physics_frame
	_chase()
	frame += 1
	if frame % shot_every == 0:
		await _shot(OS.get_environment("SCEN"))


func _steer(x: float) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	if x > 0.0:
		Input.action_press("move_right", x)
	elif x < 0.0:
		Input.action_press("move_left", -x)


func _run() -> void:
	var t := int(OS.get_environment("TYPE")) if OS.get_environment("TYPE") != "" else Vehicle.BodyType.SPORTS
	car = Vehicle.new()
	car.setup(t as Vehicle.BodyType, Color(0.75, 0.08, 0.06), Vehicle.Addon.NONE)
	add_child(car)
	car.global_position = Vector3(0, 0.9, 250)
	for i in 30:
		await get_tree().physics_frame
	car.driver = dummy
	var scen := OS.get_environment("SCEN")
	var mps := 22.0 if scen == "drift" else (15.0 if scen == "u180" else (9.0 if scen == "power" else -11.0))
	car.hold_crash_watch(3)
	car.linear_velocity = -car.global_basis.z * mps
	frame = 0
	_chase()
	match scen:
		"drift":
			Input.action_press("move_forward")
			_steer(1.0)
			Input.action_press("alt_fire")
			for i in 30:
				await _tick()
			Input.action_release("alt_fire")
			for i in 90:
				_steer(0.0)
				await _tick()
			for i in 60:
				_steer(clampf(-rad_to_deg(DriveDrift.slip_angle(car)) / 25.0, -1.0, 1.0))
				await _tick()
		"u180":
			_steer(1.0)
			Input.action_press("alt_fire")
			for i in 120:
				await _tick()
		"jturn":
			_steer(1.0)
			Input.action_press("alt_fire")
			for i in 30:
				await _tick()
			Input.action_release("alt_fire")
			_steer(0.0)
			Input.action_press("move_forward")
			for i in 90:
				await _tick()
		"power":
			Input.action_press("move_forward")
			_steer(1.0)
			for i in 150:
				await _tick()
	for a in ["move_left", "move_right", "move_forward", "move_back", "alt_fire"]:
		Input.action_release(a)
	# The marks from above.
	var c := car.global_position
	cam.global_position = Vector3(c.x * 0.5, 70.0, c.z + 25.0)
	cam.look_at(Vector3(c.x * 0.5, 0.0, (c.z + 250.0) * 0.5 - 20.0 + c.z * 0.0), Vector3.FORWARD)
	cam.global_position = Vector3(c.x * 0.5, 75.0, (c.z + 250.0) * 0.5)
	cam.look_at(Vector3(c.x * 0.5 + 0.01, 0.0, (c.z + 250.0) * 0.5), Vector3.FORWARD)
	for i in 3:
		await get_tree().process_frame
	await _shot(scen + "_top")
	print("STRIP done ", n)
	get_tree().quit()
