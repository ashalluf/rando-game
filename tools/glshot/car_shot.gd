extends SceneTree
## Close-ups of one car on a bare ground plane, several views per launch - the fast loop for
## styling a body model (a few seconds a view; the city takes minutes).
##
##   OUT=/tmp/car LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/glshot/car_shot.gd \
##     --resolution 1280x720 -- --type=0 --views=front3,rear3,side
##
## Writes $OUT_<view>.png per view. `--type=N` body type (0 sedan; see Vehicle.BodyType; the taxi,
## 17, comes in its livery, and it and the beater, 18, take their per-car look from `LOOK=n`),
## `--views` any of front3 rear3 side front rear top close (the front wheel) far (44 m out,
## narrow lens: the far twin), `--cam=x,y,z
## --look=x,y,z` for one custom view (the car's nose points -Z, its centre is the origin),
## `--fov=`, `--paint=#rrggbb`, `--finish=N` (Vehicle.Finish), `--livery=N` (Vehicle.Livery),
## `--police` (the cruiser; with `--heavy` the tactical van), `--night` (lamps lit, beams on the road), `--row=0,8,1` lines up
## several types side by side for one comparison frame (the camera then frames the row), and
## `--each=0,8,1` shoots every view of each type in turn in one launch ($OUT_t<type>_<view>.png),
## so a whole before/after set costs one wait for the render lock.
## Damage (CarDamage.stage(), real rounds and blasts through the game's own paths):
## `DAMAGE=holes,glass,dents,smoke,burning,wreck` (any mix) stages it once the car has settled,
## `WAIT=n` physics frames after that (default 30; the burning and wreck stages pre-warm their
## smoke and fire), and the views `door` (the shot-up door and wing up close), `glass` (the side
## windows), `screen` (the windscreen) and `cabin` (into an empty frame) frame it. `GEO=1` prints
## each view's draws, objects and triangles (a damaged car's cost against a whole one); `HIDE=`
## names of the car's nodes to hide (EngineFire, FireLicks, CabinFire, FireEmbers, FireSmoke).
## Occupants (CarCabin, the traced people behind the glass): `OCCUPANT=npc` (a traffic driver;
## `npc:<seed>` picks who, a seed with a passenger adds one; `pair:<seed>` always seats a front
## passenger too), `OCCUPANT=player` (the hero at the
## wheel), `OCCUPANT=none` empties a cruiser (whose crew is aboard by default); the views
## `driver` (in at the driver's window, the car's left), `inside` (through the windscreen,
## close), `street` (a pedestrian's eye 10 m off) and `chase` (behind and above) frame them; `CABIN_DEBUG=1` paints each part of the people its own flat colour.
## `CAR_GLASS=0` puts the car back on its model's own opaque glass (the A/B); `TIME=n` prints each
## view's frame time over n frames (the software renderer's fragment cost, which GEO cannot see).
## Nothing here may name Vehicle or PoliceCar as a TYPE: this script is compiled before the
## autoloads exist (CLAUDE.md).

func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _initialize() -> void:
	var type := 0
	var views := PackedStringArray(["front3"])
	var paint := Color(0.62, 0.64, 0.67)
	var finish := -1
	var livery := 0
	var cam_at := Vector3.INF
	var look := Vector3(0.0, 0.55, 0.0)
	var fov := 38.0
	var night := false
	var police := false
	var heavy := false
	var row := PackedInt32Array()
	var each := PackedInt32Array()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--type="):
			type = arg.trim_prefix("--type=").to_int()
		elif arg.begins_with("--views="):
			views = arg.trim_prefix("--views=").split(",")
		elif arg.begins_with("--paint="):
			paint = Color(arg.trim_prefix("--paint="))
		elif arg.begins_with("--finish="):
			finish = arg.trim_prefix("--finish=").to_int()
		elif arg.begins_with("--livery="):
			livery = arg.trim_prefix("--livery=").to_int()
		elif arg.begins_with("--cam="):
			cam_at = _vec(arg.trim_prefix("--cam="))
			views = PackedStringArray(["custom"])
		elif arg.begins_with("--look="):
			look = _vec(arg.trim_prefix("--look="))
		elif arg.begins_with("--fov="):
			fov = arg.trim_prefix("--fov=").to_float()
		elif arg.begins_with("--row="):
			for t in arg.trim_prefix("--row=").split(","):
				row.append(t.to_int())
		elif arg.begins_with("--each="):
			for t in arg.trim_prefix("--each=").split(","):
				each.append(t.to_int())
		elif arg == "--night":
			night = true
		elif arg == "--police":
			police = true
		elif arg == "--heavy":
			heavy = true
	# CAR_GLASS=0: the model's own opaque glass, nobody inside (CarCabin's A/B).
	if OS.get_environment("CAR_GLASS") == "0":
		(load("res://scripts/vehicles/car_cabin.gd") as GDScript).set("enabled", false)
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	if night:
		sky_mat.sky_top_color = Color(0.01, 0.012, 0.02)
		sky_mat.sky_horizon_color = Color(0.04, 0.035, 0.03)
		sky_mat.ground_horizon_color = Color(0.03, 0.025, 0.02)
		sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	# The sky's colour as DayNight publishes it (the empty frames' cabin and the building glass are
	# lit by it); the project default is a day sky.
	if night:
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.03, 0.035, 0.05))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44.0, -130.0, 0.0)
	sun.light_energy = 0.05 if night else 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	if night:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(-4.0, 6.0, 3.0)
		lamp.omni_range = 16.0
		lamp.light_energy = 2.2
		lamp.light_color = Color(1.0, 0.72, 0.42)
		world.add_child(lamp)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.20, 0.21)
	gm.roughness = 0.9
	ground.material_override = gm
	floor_body.add_child(ground)
	world.add_child(floor_body)

	var out := OS.get_environment("OUT")
	if out == "":
		out = "car_shot"
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = fov
	cam.current = true
	cam.set_meta("fov", fov)
	if each.is_empty():
		var types: Array[int] = []
		if row.is_empty():
			types.append(type)
		else:
			for t in row:
				types.append(t)
		await _shoot(world, cam, types, views, out, paint, finish, livery, police, cam_at, look, heavy)
	else:
		for t in each:
			await _shoot(world, cam, [t], views, "%s_t%d" % [out, t], paint, finish, livery, police, cam_at, look)
	quit()


func _shoot(world: Node3D, cam: Camera3D, types: Array[int], views: PackedStringArray, out: String,
		paint: Color, finish: int, livery: int, police: bool, cam_at: Vector3, look: Vector3,
		heavy: bool = false) -> void:
	var fov: float = cam.get_meta("fov", 38.0)
	var spacing := 6.2
	var cars: Array[Node3D] = []
	for i in types.size():
		var car: Node3D
		if police:
			var rng := RandomNumberGenerator.new()
			car = load("res://scripts/npc/police_car.gd").call("make", heavy, rng)
			car.set("police", null)
		elif types[i] == 12 or types[i] == 13:
			# The fire engine (12) and the ambulance (13): EmergencyCar on scene, lights running
			# (kinematic, stood at its ride height like a cruiser).
			var erng := RandomNumberGenerator.new()
			car = load("res://scripts/npc/emergency_car.gd").call("make", types[i] - 12, erng)
			car.set("lights_forced", OS.get_environment("LIGHTS") != "0")
		elif types[i] == 25 or types[i] == 26:
			# The lowriders (Lowrider; their candy, stripes and wheels from LOOK=n), parked as a
			# meet car: kinematic at its ride height, so its hydraulics can work (HYDRAULICS=hop,
			# three, dance, lift; HYD_T=seconds into it, default 1.2).
			car = load("res://scripts/vehicles/lowrider.gd").call("make", types[i], OS.get_environment("LOOK").to_int())
			car.set("traffic", {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0, "v": 0.0, "half": 2.7, "rear": 2.7, "parked": true})
			car.set("freeze_mode", 1)
			car.set("freeze", true)
		elif types[i] >= 9 and types[i] <= 11:
			# The big vehicles (BUS 9, BOX_TRUCK 10, SEMI 11) in their own liveries.
			car = load("res://scripts/vehicles/big_vehicles.gd").call("make", types[i], OS.get_environment("LOOK").to_int())
		else:
			car = load("res://scripts/vehicles/vehicle.gd").new()
			if types[i] == 17:
				# The taxi (17) in its company's livery, as random_car() turns it out.
				car.call("setup", types[i], Color(0.96, 0.73, 0.03), 0)
				car.call("setup_look", 0, 3, Color(0.07, 0.07, 0.08))
				car.set("look_seed", OS.get_environment("LOOK").to_int())
			else:
				car.call("setup", types[i], paint, 0)
				if types[i] == 18:
					car.set("look_seed", OS.get_environment("LOOK").to_int())
			if types[i] != 17 and (finish >= 0 or livery > 0):
				car.call("setup_look", maxi(finish, 1), livery, Color(0.07, 0.07, 0.08))
		# Parked, like a street car: a physics body left to settle on its springs. A cruiser is
		# kinematic until it engages, so it is stood on the road at its ride height instead.
		car.position = Vector3((float(i) - float(types.size() - 1) * 0.5) * spacing,
				float(car.call("road_lift")) if police or types[i] == 12 or types[i] == 13 or types[i] == 25 or types[i] == 26 else 0.9, 0.0)
		world.add_child(car)
		cars.append(car)
	var occupant := OS.get_environment("OCCUPANT")
	if occupant != "":
		var cabin: GDScript = load("res://scripts/vehicles/car_cabin.gd")
		for car in cars:
			if occupant.begins_with("npc"):
				var parts := occupant.split(":")
				car.set("_npc_driver", true)
				car.set("_occupant_seed", parts[1].to_int() if parts.size() > 1 else 7)
				car.call("_update_occupant")
			elif occupant.begins_with("pair"):
				# A driver and a front passenger, whatever the seed would roll.
				var parts := occupant.split(":")
				car.call("_apply_occupant", 3, cabin.call("npc_look", parts[1].to_int() if parts.size() > 1 else 7))
			elif occupant == "player":
				car.call("_apply_occupant", 1, cabin.call("player_look"))
			elif occupant == "none":
				car.call("_apply_occupant", 0, cabin.call("player_look"))
			print("OCCUPANT type %d: seats %d" % [int(car.get("body_type")), int(cabin.call("seats_of", car.call("cabin_glass")))])
			if OS.get_environment("CABIN_DEBUG") != "":
				var sm := car.call("cabin_glass") as ShaderMaterial
				if sm != null:
					sm.set_shader_parameter("cabin_debug", true)
	var hyd := OS.get_environment("HYDRAULICS")
	for car in cars:
		if car.get_node_or_null("Hydraulics") != null:
			car.get_node("Hydraulics").set("mode", 0)
	for i in 120:
		await physics_frame
	if hyd != "":
		for car in cars:
			var h: Node = car.get_node_or_null("Hydraulics")
			if h != null:
				h.call("perform", hyd, -1.0)
				h.call("advance", float(OS.get_environment("HYD_T")) if OS.get_environment("HYD_T") != "" else 1.2)
				h.set("frozen", true)
				print("HYDRAULICS %s: corners %s" % [hyd, str(h.call("heights"))])
	var damage := OS.get_environment("DAMAGE")
	if damage != "":
		for car in cars:
			car.call("damage_state").call("stage", damage)
		var wait := OS.get_environment("WAIT")
		for i in (wait.to_int() if wait != "" else 30):
			await physics_frame
		# HIDE=EngineFire,FireLicks,... hides those nodes of the car (to tell the fire's systems apart).
		var hide := OS.get_environment("HIDE")
		if hide != "":
			for car in cars:
				for n in hide.split(","):
					var node := car.find_child(n, true, false) as Node3D
					if node:
						node.visible = false
		for car in cars:
			var dmg: Object = car.call("damage_state")
			print("DAMAGE type %d: health %.0f state %d holes %d panes %s lamps %d" % [int(car.get("body_type")),
					float(dmg.get("health")), int(dmg.get("state")), int(dmg.get("holes_made")),
					str(dmg.get("pane_state")), int(dmg.get("lamps_broken"))])
	for i in 3:
		await process_frame
	# Where the physics wheels meet the road in body space: that is the body's `ride`, and the
	# generated wheel's WHEEL_POSE y is ride + the model's axle height.
	for car in cars:
		var ys := []
		for w in car.get("wheels"):
			if w.is_in_contact():
				ys.append((car.global_transform.affine_inverse() * w.get_contact_point()).y)
		var mean := 0.0
		for y in ys:
			mean += y
		if not ys.is_empty():
			mean /= ys.size()
		var d: Dictionary = car.call("_dims")
		print("CONTACT type %d: %d wheels down, road at body y %.3f (dims road %.3f, ride %.3f)" % [
				int(car.get("body_type")), ys.size(), mean, float(d.get("road", d.get("ride", -0.27))),
				float(d.get("ride", -0.27))])
	var wide := types.size() > 1
	# A big vehicle: every view pulled back by its length over a car's, aimed higher.
	var big := 1.0
	for car in cars:
		big = maxf(big, float(car.call("_dims").length) / 4.9)
	if OS.get_environment("BUS_DOORS") != "":
		for car in cars:
			var fit := car.get_node_or_null("BusFittings")
			if fit:
				fit.call("show_line", 14, "DOWNTOWN")
				if OS.get_environment("BUS_DOORS") == "1":
					fit.call("set_doors", true)
		for i in 90:
			await process_frame
	elif OS.get_environment("BUS_LINE") != "":
		for car in cars:
			var fit := car.get_node_or_null("BusFittings")
			if fit:
				fit.call("show_line", 14, "DOWNTOWN")
	for view in views:
		var at := cam_at
		var target := look
		if view != "custom":
			match view:
				"front":
					at = Vector3(0.0, 1.0, -8.5)
				"rear":
					at = Vector3(0.0, 1.1, 8.5)
				"side":
					at = Vector3(9.5, 0.85, 0.0)
				"rear3":
					at = Vector3(5.0, 1.45, 6.0)
				"top":
					at = Vector3(5.0, 5.5, -4.5)
				"close":
					at = Vector3(3.2, 0.7, -3.6)
					target = Vector3(0.9, 0.3, -1.5)
				"door":
					at = Vector3(3.4, 0.95, -1.6)
					target = Vector3(0.9, 0.45, -0.6)
				"glass":
					at = Vector3(4.2, 1.35, 0.4)
					target = Vector3(0.8, 0.95, 0.05)
				"screen":
					at = Vector3(1.6, 2.1, -5.2)
					target = Vector3(0.0, 0.95, -1.0)
				"cabin":
					at = Vector3(2.6, 1.25, -0.3)
					target = Vector3(0.0, 0.85, -0.3)
				"driver":
					at = Vector3(-3.1, 1.4, -0.1)
					target = Vector3(-0.3, 0.95, -0.35)
				"inside":
					at = Vector3(-0.9, 1.7, -4.4)
					target = Vector3(-0.2, 0.95, -0.4)
				"street":
					# A pedestrian's eye across the street, the driver's side toward it.
					at = Vector3(-6.5, 1.7, -7.5)
					target = Vector3(0.0, 0.8, -0.3)
				"chase":
					# Behind and above, where the player's camera follows a car.
					at = Vector3(1.2, 2.6, 8.5)
					target = Vector3(0.0, 0.9, -1.0)
				"far":
					# Past Vehicle.body_far_distance, with a narrow lens: the far twin.
					at = Vector3(26.0, 5.0, -36.0)
				_:
					at = Vector3(5.0, 1.35, -6.2)
			if wide:
				at *= 1.0 + 0.55 * float(types.size() - 1)
			if big > 1.0 and cam_at == Vector3.INF:
				at = Vector3(at.x * sqrt(big), at.y * sqrt(big), at.z * big)
				target = Vector3(target.x, target.y * sqrt(big) * 1.3, target.z * big)
		cam.fov = 9.0 if view == "far" else fov
		cam.look_at_from_position(at, target)
		for i in 4:
			await process_frame
		var path := "%s_%s.png" % [out, view]
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
		if OS.get_environment("TIME") != "":
			# Frame time over TIME=n frames of this view (a software renderer: the fragment cost
			# of what is on screen shows here, where GEO counts only geometry).
			var n := OS.get_environment("TIME").to_int()
			var t0 := Time.get_ticks_usec()
			for i in n:
				await process_frame
			print("TIME %s %.2f ms a frame over %d" % [view, float(Time.get_ticks_usec() - t0) / 1000.0 / float(n), n])
		if OS.get_environment("GEO") != "":
			# The frame's cost (opengl3 only; --headless reads zero): draws, objects, triangles.
			print("GEO %s draws %d objects %d tris %d" % [view,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	for car in cars:
		car.queue_free()
	await process_frame
