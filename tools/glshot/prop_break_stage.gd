extends RefCounted
## The stage of tools/glshot/prop_break_shot.gd (loaded at run time, after the autoloads).

var _tree: SceneTree
var _chunk: CityChunk
var _car: Vehicle


func run(tree: SceneTree) -> void:
	_tree = tree
	var night := OS.get_environment("NIGHT") == "1"
	var stage := Node3D.new()
	stage.name = "Stage"
	_tree.root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) if not night else Color(0.05, 0.04, 0.04)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45) if not night else Color(0.03, 0.03, 0.03)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18) if not night else Color(0.01, 0.01, 0.01)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45 if not night else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25 if not night else 1.6
	e.glow_enabled = night
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.66, 0.75, 0.88) if not night else Color(0.05, 0.05, 0.07))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Road and pavement, solid.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	stage.add_child(ground)
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(80.0, 0.1 if i == 0 else 0.25, 16.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else 0.125, 8.0 if i == 0 else -8.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.11, 0.11, 0.115) if i == 0 else Color(0.3, 0.29, 0.28)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
		var c := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		c.shape = bs
		c.position = g.position
		ground.add_child(c)
	# A real chunk, with no plan (no relief), holding the props.
	_chunk = CityChunk.new()
	_chunk.key = "prop_break_shot"
	_chunk.name = "Chunk_shot"
	_chunk._statics = StreetProps.new()
	_chunk._statics.chunk = _chunk
	_chunk.add_child(_chunk._statics)
	stage.add_child(_chunk)
	var top := 0.25
	var x := -10.0
	# Hydrant.
	var at := Vector3(x, top, -0.8)
	_chunk._add_prop("hydrant", at, Color(0.85, 0.15, 0.12), [["hydrant", PropFactory.model_hydrant(false), Transform3D(Basis(Vector3.UP, 0.4), at)]], [[Vector3(0.3, 0.8, 0.3), at + Vector3(0.0, 0.4, 0.0), 0.0]])
	# Lamp.
	x += 4.0
	at = Vector3(x, top, -0.6)
	var lp := StreetLamps.place(null, at, Vector2(0.0, 1.0), 0)
	_chunk._add_prop("lamp", at, Color(0.28, 0.29, 0.32), [[lp.key, lp.mesh, lp.xform, lp.paint, lp.custom]], [[lp.box, at + Vector3(0.0, (lp.box as Vector3).y * 0.5, 0.0), 0.0]])
	# Bus shelter (StreetDetail._bus_shelter's pieces), facing the road (+z).
	x += 5.0
	at = Vector3(x, top, -1.2)
	var yaw := atan2(0.0, -1.0)
	var basis := Basis(Vector3.UP, yaw + PI)
	var back := Vector3(0.0, 0.0, -0.9)
	var along := Vector3(1.0, 0.0, 0.0)
	_chunk._add_prop("bus_stop", at, Color(0.3, 0.3, 0.32), [
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back + along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back - along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_roof", PropFactory.shelter_roof(), Transform3D(basis, at + back * 0.4 + Vector3(0.0, 2.55, 0.0))],
		["shelter_glass", PropFactory.shelter_glass(), Transform3D(basis, at + back + Vector3(0.0, 1.3, 0.0))],
		["bench", PropFactory.model_bench(), Transform3D(Basis(Vector3.UP, yaw), at + back * 0.55)],
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + along * 2.6 + Vector3(0.0, 1.4, 0.0))],
		["bus_sign", PropFactory.bus_sign(), Transform3D(basis, at + along * 2.6 + Vector3(0.0, 2.7, 0.0))],
	], [[Vector3(4.2, 2.6, 1.0), at + back + Vector3(0.0, 1.3, 0.0), yaw]])
	# Mailbox.
	x += 5.0
	at = Vector3(x, top, -0.9)
	_chunk._add_prop("mailbox", at, Color(0.15, 0.3, 0.25), [["mailbox", PropFactory.mailbox(), Transform3D(Basis(Vector3.UP, PI), at)]], [[Vector3(0.6, 1.3, 0.5), at + Vector3(0.0, 0.65, 0.0), PI]])
	# Parking meter.
	x += 3.0
	at = Vector3(x, top, -0.45)
	_chunk._add_prop("meter", at, Color(0.32, 0.33, 0.34), [["meter", StreetDetail._meter_mesh(), Transform3D(Basis(Vector3.UP, PI), at)]], [[Vector3(0.2, 1.4, 0.2), at + Vector3(0.0, 0.7, 0.0), PI]])
	# News box.
	x += 3.0
	at = Vector3(x, top, -1.0)
	_chunk._add_prop("newsbox", at, Color(0.1, 0.3, 0.7), [[StreetClutter.K_NEWS, StreetClutter.news_box(), Transform3D(Basis(Vector3.UP, PI), at), Color.WHITE, Color(0.1, 0.3, 0.7, 0.4)]], [[Vector3(0.5, 1.12, 0.44), at + Vector3(0.0, 0.56, 0.0), PI]])
	_chunk._mm_nodes = _chunk._batch.build(_chunk)
	print("PROPS ", _chunk.prop_records.size())

	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-1.0, 2.2, 12.0)), _vec(OS.get_environment("LOOK"), Vector3(-1.0, 1.4, -1.0)), Vector3.UP)
	cam.make_current()
	for i in 6:
		await _tree.process_frame

	var caps: Array = []
	for c in (OS.get_environment("CAPS") if OS.get_environment("CAPS") != "" else "-1,0.25,1.2").split(","):
		caps.append(c.to_float())
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "prop_break"
	var n := 0
	for c in caps:
		if c < 0.0:
			await _shot("%s_%d.png" % [out, n])
		n += 1
	var which := (OS.get_environment("BREAK") if OS.get_environment("BREAK") != "" else "hydrant,lamp,bus_stop,mailbox,meter,newsbox").split(",")
	if OS.get_environment("CAR") == "1":
		_drive_car(stage)
	else:
		for r in _chunk.prop_records:
			var dir := Vector3(0.15, 0.0, -1.0).normalized()
			if which.has("lean") and r.kind == "lamp":
				_chunk.damage_prop(r, 45.0, dir)
			elif which.has("glass") and r.kind == "bus_stop":
				_chunk.damage_prop(r, 50.0, dir)
			elif which.has(r.kind):
				_chunk.damage_prop(r, 200.0 if r.kind != "bus_stop" else 400.0, dir)
				if r.kind == "bus_stop" and not r.dead:
					_chunk.damage_prop(r, 400.0, dir)
	var t := 0.0
	n = 0
	for c in caps:
		if c >= 0.0:
			while t < c:
				await _tree.physics_frame
				t += 1.0 / Engine.physics_ticks_per_second
				if OS.get_environment("DEBUG") == "1" and _car:
					print("CAR t=%.2f x=%.2f v=%.2f" % [t, _car.global_position.x, _car.linear_velocity.length()])
				if OS.get_environment("DEBUG") == "1":
					for b in _chunk.get_children():
						if b is FallingPole:
							print("POLE t=%.2f tilt=%.2f pos=%s" % [t, b.tilt(), b.position])
			await _shot("%s_%d.png" % [out, n])
		n += 1
	_tree.quit()


func _drive_car(stage: Node3D) -> void:
	var speed := float(OS.get_environment("CAR_SPEED")) if OS.get_environment("CAR_SPEED") != "" else 14.0
	var car := Vehicle.new()
	_car = car
	car.setup(Vehicle.BodyType.SEDAN, Color(0.15, 0.2, 0.45), Vehicle.Addon.NONE)
	stage.add_child(car)
	car.global_position = Vector3(-24.0, 0.8, -0.6)
	car.rotation.y = -PI * 0.5
	car.linear_velocity = Vector3(speed, 0.0, 0.0)


func _shot(path: String) -> void:
	await _tree.process_frame
	await _tree.process_frame
	_tree.root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
