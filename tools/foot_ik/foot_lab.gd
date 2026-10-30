extends Node3D
## A bare lab for the crowd's foot placement (CrowdFeet): real Pedestrians on a kerb, a slope
## and a flight of stairs, with nothing else in the world. A scene, so the autoloads exist.
##
##   OUT=/tmp/feet SHOTS=kerb,ramp,stairs,walk LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --resolution 1280x720 tools/foot_ik/foot_lab.tscn
## FOOT_IK=0 is the before. MODE=bench (headless) times N people (default 40) walking round
## the camera on the flat: the physics step's process time with and without (run it twice). Headless (`--headless`) it prints, per person, the feet's planted
## error: how far each sole is from the ground found under it (m), with and without the IK.
## SHOTS: kerb (three people at a 15 cm kerb edge, one foot over it), ramp (people across and
## along a 14-degree slope), stairs (people on 17 x 30 cm steps), walk (one walking up the ramp:
## FRAMES frames STEP ticks apart). CAM=x,y,z / LOOK=x,y,z / FOV override the camera.

const KERB := 0.15
const RAMP_DEG := 14.0
const RISE := 0.17
const RUN := 0.30

var _peds: Array = []
var _cam: Camera3D


func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1
	_world()
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	if OS.get_environment("MODE") == "bench":
		await _bench()
		get_tree().quit()
		return
	_stage()
	for i in 40:
		await get_tree().physics_frame
	if DisplayServer.get_name() == "headless":
		for p: Pedestrian in _peds:
			if p.foot_ik:
				p.foot_ik.debug = true
		await get_tree().physics_frame
		_report()
		await _walk_report()
		get_tree().quit()
		return
	var out := _env("OUT", "foot_lab")
	DirAccess.make_dir_recursive_absolute(out)
	for shot in _env("SHOTS", "kerb,ramp,stairs").split(","):
		if shot == "walk":
			await _walk(out)
			continue
		_aim(shot)
		for i in 4:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shot])
		print("foot_lab: %s/%s.png" % [out, shot])
	get_tree().quit()


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return fallback if v == "" else v


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## A static box with a mesh: centre, size, rotation about x (deg).
func _box(centre: Vector3, size: Vector3, c: Color, tilt_x: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	body.add_child(mi)
	body.position = centre
	body.rotation_degrees.x = tilt_x
	add_child(body)


func _world() -> void:
	# The road (y 0), a pavement along x < 0 at z in [-6, 0] with its kerb edge at z = 0.
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.2, 0.2, 0.21))
	_box(Vector3(-10, KERB * 0.5, -3), Vector3(20, KERB, 6), Color(0.55, 0.54, 0.5))
	# A ramp along -z at x in [10, 16]: rises toward -z.
	var a := deg_to_rad(RAMP_DEG)
	var length := 14.0
	_box(Vector3(13, length * 0.5 * sin(a) - 0.25 * cos(a), -length * 0.5 * cos(a)), Vector3(6, 0.5, length), Color(0.5, 0.46, 0.38), RAMP_DEG)
	# Stairs at x in [24, 28], climbing toward -z from z = 0.
	for i in 10:
		var h := RISE * float(i + 1)
		_box(Vector3(26, h * 0.5, -RUN * (float(i) + 0.5)), Vector3(4, h, RUN), Color(0.6, 0.6, 0.58))
	if OS.get_environment("STAIR_RAMP") == "1":
		# The steps on the feet layer under a walkable world-layer ramp through their nosings
		# (the Esplanade's beach stairs), the ramp seen through by the feet.
		for body in get_children():
			if body is StaticBody3D and (body as StaticBody3D).position.x == 26.0:
				body.collision_layer = CrowdFeet.FEET_LAYER
		var ang := atan2(RISE, RUN)
		var ramp := StaticBody3D.new()
		ramp.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4, 0.3, 10.0 * RUN / cos(ang))
		cs.shape = bs
		cs.set_meta("feet_pass", true)
		ramp.add_child(cs)
		ramp.position = Vector3(26, RISE + RISE * 5.0 - 0.15 * cos(ang), -RUN * 5.0 - 0.15 * sin(ang))
		ramp.rotation.x = ang
		add_child(ramp)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 140, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.67, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.84)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true


## One person standing still at (x, y, z) facing yaw (deg; 0 faces -z).
func _stand(at: Vector3, yaw: float, seed_value: int) -> Pedestrian:
	var p := Pedestrian.new()
	p.setup(Rect2(at.x - 50, at.z - 50, 100, 100), 4.0, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_spawn_chance = 0.0
	p.life_chance = 0.0
	p.position = at
	add_child(p)
	p._pause_left = 100000.0
	p._visual.rotation.y = deg_to_rad(yaw)
	p._play_idle()
	p._speed = 0.0
	_peds.append(p)
	return p


func _ramp_y(z: float) -> float:
	return -z * tan(deg_to_rad(RAMP_DEG))


func _stage() -> void:
	# Kerb: side-on to the edge (one foot over it), facing the road, and just back from it.
	_stand(Vector3(-4.0, KERB, -0.08), 90.0, 11)
	_stand(Vector3(-2.6, KERB, -0.12), 180.0 + 90.0, 29)
	_stand(Vector3(-1.2, KERB, -0.25), 180.0, 47)
	# Ramp: across the slope (feet at two heights), facing up it, facing down it.
	_stand(Vector3(11.6, _ramp_y(-4.0) + 0.05, -4.0), 90.0, 61)
	_stand(Vector3(13.0, _ramp_y(-5.0) + 0.05, -5.0), 0.0, 73)
	_stand(Vector3(14.4, _ramp_y(-4.4) + 0.05, -4.4), 180.0, 89)
	# Stairs: facing up, side-on, facing down.
	_stand(Vector3(24.8, RISE * 4 + 0.05, -RUN * 3.6), 0.0, 101)
	_stand(Vector3(26.0, RISE * 6 + 0.05, -RUN * 5.5), 90.0, 113)
	_stand(Vector3(27.2, RISE * 3 + 0.05, -RUN * 2.5), 180.0, 127)


func _aim(shot: String) -> void:
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 34.0
	match shot:
		"kerb":
			pos = Vector3(-2.6, 0.55, 3.2)
			look = Vector3(-2.6, 0.45, -0.1)
		"ramp":
			pos = Vector3(18.6, 1.7, -4.6)
			look = Vector3(13.0, 1.25, -4.6)
			fov = 30.0
		"stairs":
			pos = Vector3(30.8, 1.45, -1.3)
			look = Vector3(26.0, 0.95, -1.3)
			fov = 32.0
	if OS.get_environment("CAM") != "":
		var c := OS.get_environment("CAM").split_floats(",")
		pos = Vector3(c[0], c[1], c[2])
	if OS.get_environment("LOOK") != "":
		var l := OS.get_environment("LOOK").split_floats(",")
		look = Vector3(l[0], l[1], l[2])
	if OS.get_environment("FOV") != "":
		fov = float(OS.get_environment("FOV"))
	_cam.fov = fov
	_cam.position = pos
	_cam.look_at(look, Vector3.UP)


## One person walking up the ramp, filmed side-on.
func _walk(out: String) -> void:
	var p := Pedestrian.new()
	p.setup(Rect2(-50, -50, 100, 100), 4.0, 211)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_spawn_chance = 0.0
	p.life_chance = 0.0
	p.position = Vector3(15.2, _ramp_y(-1.5) + 0.05, -1.5)
	add_child(p)
	var frames := int(_env("FRAMES", "8"))
	var step := int(_env("STEP", "10"))
	for f in frames:
		for t in step:
			p._target = Vector2(15.2, -12.0)
			p._route = PackedVector2Array()
			p._route_pending = false
			await get_tree().physics_frame
		var at := p.global_position
		_cam.fov = 34.0
		_cam.position = at + Vector3(5.0, 0.4, 0.0)
		_cam.look_at(at + Vector3(0, 0.7, 0), Vector3.UP)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/walk_%02d.png" % [out, f])
	print("foot_lab: walk frames to %s" % out)


## Per person: each sole's distance over the ground under it (+ floating, - sunk).
func _report() -> void:
	var space := get_world_3d().direct_space_state
	var worst := 0.0
	for p: Pedestrian in _peds:
		var sk: Skeleton3D = p._head_skel
		var line := "foot_lab %s:" % p.name
		for b in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
			var at := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * 0.6, 1)
			var hit := space.intersect_ray(q)
			var gap: float = (at.y - hit.position.y) if not hit.is_empty() else INF
			line += " %s %+.3f" % [b, gap]
		var f: CrowdFeet = p.foot_ik
		if f:
			line += "  lift %s hips %+.3f" % [f.applied_lift, f.applied_hips]
			for l in f.debug_lines:
				line += "\n    " + l
		print(line)


## Headless: a walker up and then down the ramp; for every tick, the lower foot's ankle over the
## ground under it, against the same on the flat (the clip's own planted height). Prints the mean
## and worst error of that planted foot on the slope (m).
func _walk_report() -> void:
	var space := get_world_3d().direct_space_state
	for leg in [[Vector2(15.2, 1.5), Vector2(15.2, -6.0), "flat road then up the ramp"], [Vector2(15.2, -11.0), Vector2(15.2, -2.0), "down the ramp"]]:
		var p := Pedestrian.new()
		p.setup(Rect2(-50, -50, 100, 100), 4.0, 211)
		p.pause_chance = 0.0
		p.cross_chance = 0.0
		p.life_spawn_chance = 0.0
		p.life_chance = 0.0
		var start: Vector2 = leg[0]
		var y := _ramp_y(start.y) if start.y < 0.0 else 0.0
		p.position = Vector3(start.x, y + 0.05, start.y)
		add_child(p)
		var flat: Array = []
		var slope: Array = []
		for t in 300:
			p._target = leg[1]
			p._route = PackedVector2Array()
			p._route_pending = false
			await get_tree().physics_frame
			if t < 30:
				continue
			var sk: Skeleton3D = p._head_skel
			var best := INF
			for b in ["LeftFoot", "RightFoot"]:
				var at := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * 0.8, 1))
				if not hit.is_empty():
					best = minf(best, at.y - hit.position.y)
			if best == INF:
				continue
			var z := p.global_position.z
			if z > 0.5:
				flat.append(best)
			elif z < -1.5 and z > -11.5:
				slope.append(best)
		var fm := 0.0
		for v in flat:
			fm += v
		fm = fm / maxf(flat.size(), 1)
		if flat.is_empty():
			fm = 0.13
		var err := 0.0
		var worst := 0.0
		for v in slope:
			err += absf(v - fm)
			worst = maxf(worst, absf(v - fm))
		print("foot_lab walk %s: planted ankle on flat %.3f, on the slope mean error %.3f worst %.3f (%d ticks)" % [leg[2], fm, err / maxf(slope.size(), 1), worst, slope.size()])
		p.queue_free()


func _bench() -> void:
	var n := int(_env("N", "40"))
	_cam.position = Vector3(0, 1.6, 0)
	for i in n:
		var p := Pedestrian.new()
		var a := TAU * float(i) / float(n)
		p.setup(Rect2(-9, -9, 18, 18), 4.0, 500 + i)
		p.position = Vector3(cos(a) * 7.0, 0.05, sin(a) * 7.0)
		add_child(p)
	for i in 120:
		await get_tree().physics_frame
	var total := 0.0
	var ticks := 600
	for i in ticks:
		await get_tree().physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("foot_lab bench: FOOT_IK=%s N=%d physics process %.3f ms a tick" % [OS.get_environment("FOOT_IK"), n, total / ticks * 1000.0])
