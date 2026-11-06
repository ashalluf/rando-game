extends SceneTree
## One car of each body type on a bare ground plane, seen from the side, so the generated wheels
## can be checked against the arches of the body model without waiting for the city to stream.
## Roughly twenty seconds where the showroom shot is eight minutes.
##
##   OUT=cars.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1600x900x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/car_wheel_shot.gd --resolution 1600x900 -- --type=0 --view=side
##
## `--type=N` is one body type (omit for the whole row), `--view` is side / front / three
## and `--dist` scales the camera back. Nothing here may name Vehicle as a TYPE: this script is
## compiled before the autoloads exist and Vehicle reaches for Sfx (CLAUDE.md).

func _initialize() -> void:
	var only := -1
	var view := "side"
	var dist := 1.0
	var paint := Color(0.70, 0.13, 0.11)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--type="):
			only = arg.trim_prefix("--type=").to_int()
		elif arg.begins_with("--view="):
			view = arg.trim_prefix("--view=")
		elif arg.begins_with("--dist="):
			dist = arg.trim_prefix("--dist=").to_float()
		elif arg.begins_with("--paint="):
			paint = Color(arg.trim_prefix("--paint="))
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44.0, -120.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)

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
	ground.material_override = PropFactory.material(Color(0.30, 0.30, 0.31), 0.88)
	floor_body.add_child(ground)
	world.add_child(floor_body)

	var script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var types: Array = [only] if only >= 0 else range(8)
	var pitch := 6.0
	for i in types.size():
		var car: Node3D = script.new()
		car.call("setup", types[i], paint, 0)
		car.position = Vector3((float(i) - float(types.size() - 1) * 0.5) * pitch, 0.9, 0.0)
		car.rotation.y = PI * 0.5
		world.add_child(car)

	# Let the suspension settle, or every car is caught mid-drop.
	for i in 90:
		await physics_frame
	for i in 3:
		await process_frame

	var cam := Camera3D.new()
	var span := pitch * float(types.size())
	var back := maxf(span * 0.5 / tan(deg_to_rad(28.0)), 4.0) * dist
	match view:
		"front":
			cam.position = Vector3(0.0, 0.85, -back)
			cam.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
		"three":
			cam.position = Vector3(back * 0.55, 1.10, -back * 0.62)
			cam.look_at_from_position(Vector3(back * 0.55, 1.10, -back * 0.62), Vector3(0.0, 0.5, 0.0))
		_:
			cam.position = Vector3(0.0, 0.70, back)
			cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	cam.fov = 58.0
	world.add_child(cam)
	cam.current = true
	for i in 3:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "car_wheel_shot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
