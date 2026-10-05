extends Node3D
## The golfers' poses on their own (Golfer): a row of them on a flat green, frozen at points of
## their timelines - address, the top, the finish, a putt, and one seated as in a cart - and a
## golf cart, lit like the city's noon. A scene, so the autoloads exist before Pedestrian compiles.
##   OUT=/tmp/golfers.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --resolution 1280x720 tools/golf/golfer_lab.tscn
## Env: YAW (camera orbit, degrees; 0 faces the row's fronts), CAM_DIST, CAM_Y, MODEL (seed offset).

const STAGES := [["address", 2.0], ["top", 4.3], ["impact", 4.58], ["finish", 5.6], ["putt", 3.0], ["ride", 0.0], ["wait", 0.0]]


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.7, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.76, 0.86)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	ground.material_override = PropFactory.material(Color(0.25, 0.45, 0.18))
	add_child(ground)
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(0.0, 0.0, 8.0)
	add_child(player)
	var seed_off := int(OS.get_environment("MODEL")) if OS.get_environment("MODEL") != "" else 0
	var golfers: Array = []
	for i in STAGES.size():
		var st: Array = STAGES[i]
		var role := Golfer.Role.DRIVE
		match String(st[0]):
			"putt":
				role = Golfer.Role.PUTT
			"ride":
				role = Golfer.Role.RIDE
			"wait":
				role = Golfer.Role.WAIT
		var g := Golfer.new()
		var x := (float(i) - float(STAGES.size() - 1) * 0.5) * 1.9
		# Target to the left of the row (-x): the golfers face the camera (+z).
		g.setup_golfer(Vector2(x, 0.0), 0.0, Vector2(-1.0, 0.0), role, 100 + i + seed_off)
		add_child(g)
		golfers.append([g, float(st[1])])
	var cart := MeshInstance3D.new()
	cart.mesh = GolfLife.cart_mesh()
	cart.position = Vector3(8.5, 0.0, -2.0)
	cart.rotation_degrees.y = -60.0
	add_child(cart)
	var cam := Camera3D.new()
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.0)
	var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 10.0
	var cy := float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.3
	cam.fov = 50.0
	add_child(cam)
	cam.look_at_from_position(Vector3(sin(yaw) * dist, cy, cos(yaw) * dist), Vector3(0.0, 0.9, 0.0))
	cam.make_current()
	for f in 4:
		await get_tree().process_frame
	for gg: Array in golfers:
		var g: Golfer = gg[0]
		if g.role == Golfer.Role.DRIVE or g.role == Golfer.Role.PUTT:
			g.set_physics_process(false)
			g._pose_at(float(gg[1]))
	for f in 6:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/golfers.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
