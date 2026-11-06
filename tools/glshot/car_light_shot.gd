extends SceneTree
## The player's car at night in a small street of its own: its headlights on a wall ahead, an
## oncoming traffic car with its own, a parked car (dark) - CarLights and the lamp mesh without
## the city, so it renders on lavapipe (Forward+, the renderer the lights are for) in a minute or
## two, and on opengl3 in seconds (CarLights forced on).
##
##   OUT=/tmp/carlight.png xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/car_light_shot.gd --resolution 960x540
##
## Env: OUT png path; NOLIGHTS=1 no CarLights (the lamp mesh alone, what the web draws: the
## "before"); BRAKE=1 holds the player's handbrake (brake lamps, the red glow behind); REVERSE=1
## reverses; VIEW=chase (default, behind the car toward the wall) | rear (behind, looking back at
## the tail) | side | top (high, the beams on the road); PSHADOW=0 the player's headlight without its shadow; WALL=metres to the wall (default 16); FRAMES before the shot (default 40); AHEAD=1 the traffic car drives
## away from the camera (its tail lamps); OLDMAT=1 both cars' lamps on the old light_pool material
## (the A/B of car_lights.gdshader); TYPE the
## player's body type (Vehicle.BodyType, default 0).
## Nothing here names Vehicle or CarLights as a TYPE (compiled before the autoloads exist).

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _initialize() -> void:
	var lights_script: GDScript = load("res://scripts/vehicles/car_lights.gd")
	lights_script.set("force", true)
	lights_script.set("lamp_override", 1.0)
	if _env("NOCOOKIE", "0") == "1":
		lights_script.set("cookie_enabled", false)
	if _env("PSHADOW", "1") == "0":
		lights_script.set("player_shadow", false)
	if _env("NOLIGHTS", "0") == "1":
		lights_script.set("budget", 0)
		lights_script.set("player_light", false)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.04
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	world.add_child(moon)
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	var wall_z := -float(_env("WALL", "16"))
	_slab(world, Vector3(60.0, 0.2, 80.0), Vector3(0.0, -0.1, -10.0), pf.call("pbr", "asphalt", 5.0))
	_slab(world, Vector3(5.0, 0.15, 80.0), Vector3(6.6, 0.075, -10.0), pf.call("pbr", "sidewalk", 3.0))
	_slab(world, Vector3(5.0, 0.15, 80.0), Vector3(-6.6, 0.075, -10.0), pf.call("pbr", "sidewalk", 3.0))
	_slab(world, Vector3(30.0, 9.0, 1.0), Vector3(0.0, 4.5, wall_z - 0.5), pf.call("pbr", "brick", 3.0))
	_slab(world, Vector3(1.0, 9.0, 40.0), Vector3(9.6, 4.5, -10.0), pf.call("pbr", "plaster_beige", 3.0))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 80.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.1, -10.0)
	world.add_child(body)
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	var vs: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var mine: Node = _car(world, vs, int(_env("TYPE", "0")), Color(0.55, 0.06, 0.05), Vector3(1.8, 0.6, 0.0), 0.0, false)
	# AHEAD=1: the traffic car drives away from the camera instead, at 8 m/s (its tail lamps).
	var ahead := _env("AHEAD", "0") == "1"
	var oncoming: Node = _car(world, vs, 8, Color(0.8, 0.8, 0.82), Vector3(-1.8, 0.6, wall_z + 8.0), 0.0 if ahead else PI, true)
	if ahead:
		oncoming.get("traffic").dir = -1
		oncoming.get("traffic").turn = 0
		oncoming.set("traffic_speed", 8.0)
	_car(world, vs, 1, Color(0.1, 0.1, 0.12), Vector3(4.0, 0.6, -6.0), 0.0, false)
	await physics_frame
	await physics_frame
	mine.set("driver", player)
	if _env("BRAKE", "0") == "1":
		Input.action_press("alt_fire")
	if _env("REVERSE", "0") == "1":
		Input.action_press("move_back")
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	match _env("VIEW", "chase"):
		"rear":
			cam.look_at_from_position(Vector3(0.5, 1.6, 9.0), Vector3(1.8, 0.4, 0.0))
		"top":
			cam.look_at_from_position(Vector3(-3.0, 11.0, 6.0), Vector3(1.0, 0.0, wall_z * 0.5))
		"side":
			cam.look_at_from_position(Vector3(-5.0, 1.7, 2.0), Vector3(1.0, 0.8, wall_z * 0.6))
		_:
			cam.look_at_from_position(Vector3(0.6, 3.4, 8.5), Vector3(1.4, 0.3, wall_z))
	cam.current = true
	for i in int(_env("FRAMES", "40")):
		await process_frame
	if _env("OLDMAT", "0") == "1":
		for c in [mine, oncoming]:
			(c.get_node("NightLights") as MeshInstance3D).material_override = pf.call("light_pool_material")
	await process_frame
	await process_frame
	for c in [mine, oncoming]:
		var nl: MeshInstance3D = c.get_node_or_null("NightLights")
		var mat: ShaderMaterial = nl.material_override if nl else null
		print("LAMPS %s visible=%s brake=%s signal=%s aabb=%s" % [c.call("display_name"), nl.visible if nl else null, mat.get_shader_parameter("brake") if mat else null, mat.get_shader_parameter("signal_side") if mat else null, nl.get_aabb() if nl else null])
	var out := _env("OUT", "carlight.png")
	root.get_texture().get_image().save_png(out)
	print("saved %s, car lights %d, oncoming brake %s signal %s" % [out, int(lights_script.get("active_count")), oncoming.get("light_brake"), oncoming.get("light_signal")])
	quit()


func _slab(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


func _car(parent: Node3D, vs: GDScript, type: int, paint: Color, at: Vector3, yaw: float, traffic: bool) -> Node:
	var car: Node = vs.new()
	car.call("setup", type, paint, 0)
	if traffic:
		car.set("traffic", {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0, "turn": -1, "to_c": 20.0})
		car.set("freeze_mode", RigidBody3D.FREEZE_MODE_KINEMATIC)
		car.set("freeze", true)
		at.y = float(car.call("road_lift"))
	car.set("position", at)
	car.set("rotation", Vector3(0.0, yaw, 0.0))
	parent.add_child(car)
	return car
