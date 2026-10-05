extends SceneTree
## Building damage (BuildingDamage) on one generated Building, shot with the real OpenGL renderer:
## the building on a ground slab, the damage dealt through the real entry points (rounds are
## physics rays handed to BuildingDamage.bullet(), a blast is Explosion.blast()), then a still.
##
##   OUT=shot.png MODE=storefront BSEED=7 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/damage_shot.gd --resolution 960x540
##
## MODE: storefront (rounds along the shop windows: some crazed, some gone, scars between),
## office (a row of windows shot out on one floor, and some crazed above), hole (a rocket-sized
## blast against the wall at the foot of the facade), none (the same frame undamaged).
## Env as building_shot.gd: BSEED, FINISH, LOT, HMIN / HMAX, KIT=0, NIGHT=1, CAM_POS / CAM_LOOK /
## CAM_FOV (building space; default frames the +Z face), FLOOR (office: which floor, default 2),
## WAIT (frames after the damage, default 40: the shards fall, the dust rolls).
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.7, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 25, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	for i in 3:
		await process_frame
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.62, 0.72, 0.86, 1.0))
	RenderingServer.global_shader_parameter_set("sun_direction", -sun.global_basis.z)
	var night := OS.get_environment("NIGHT") == "1"
	if night:
		RenderingServer.global_shader_parameter_set("night_factor", 1.0)
		RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.05, 0.06, 0.09, 1.0))
		e.background_color = Color(0.02, 0.025, 0.04)
		e.ambient_light_color = Color(0.05, 0.06, 0.09)
		sun.light_energy = 0.05
	if OS.get_environment("KIT") == "0":
		(load("res://scripts/world/building.gd") as GDScript).set("kit_enabled", false)
	# The street: a slab the glass and the rubble land on.
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(300, 1, 300)
	gs.shape = gb
	gs.position.y = -0.5
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	gm.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.32, 0.31)
	gmat.roughness = 0.9
	gm.material_override = gmat
	ground.add_child(gm)
	root3d.add_child(ground)
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var b := scene.instantiate()
	b.seed = _env_int("BSEED", 7)
	var lot := float(_env_int("LOT", 26))
	b.lot_size = Vector2(lot, lot)
	b.min_height = float(_env_int("HMIN", 18))
	b.max_height = float(_env_int("HMAX", 30))
	var fin := OS.get_environment("FINISH")
	if fin != "":
		b.finish_options.assign([int(fin)])
	# NOSHOP=1: no storefront, the wall runs to the pavement (the rocket-hole still).
	# LIT=1: most offices lit after dark (the night still of a shot-out row).
	if OS.get_environment("LIT") == "1":
		b.lit_ratio_range = Vector2(0.9, 0.95)
	if OS.get_environment("NOSHOP") == "1":
		b.allow_storefront = false
	root3d.add_child(b)
	# The +Z face of the ground part: where the rounds land.
	var front := 0.0
	var width := 10.0
	var gfh := 4.5
	var floor_h := 3.5
	var pitch := 2.5
	for part: Dictionary in b.parts:
		var c: Vector3 = part.center
		var s: Vector3 = part.size
		if c.y - s.y * 0.5 < 0.1 and c.z + s.z * 0.5 > front:
			front = c.z + s.z * 0.5
			width = s.x
			gfh = float(part.get("gfh", 4.5))
			floor_h = float(part.get("floor_h", 3.5))
			pitch = float(part.get("pitch_x", 2.5))
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.far = 2000.0
	cam.current = true
	var pos_s := OS.get_environment("CAM_POS")
	if pos_s != "":
		var p := pos_s.split_floats(",")
		var l := OS.get_environment("CAM_LOOK").split_floats(",")
		cam.look_at_from_position(Vector3(p[0], p[1], p[2]), Vector3(l[0], l[1], l[2]))
	else:
		cam.look_at_from_position(Vector3(width * 0.25, 3.5, front + 15.0), Vector3(0.0, 4.5, front))
	if OS.get_environment("CAM_FOV") != "":
		cam.fov = OS.get_environment("CAM_FOV").to_float()
	for i in 4:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
	var mode := OS.get_environment("MODE")
	# Reached through their script resources: this script compiles before the autoloads exist.
	var bd: GDScript = load("res://scripts/world/building_damage.gd")
	var fx: GDScript = load("res://scripts/weapons/weapon_fx.gd")
	var ex: GDScript = load("res://scripts/weapons/explosion.gd")
	var ws := get_root().get_node("/root/WorldState")
	var shoot := func(x: float, y: float) -> void:
		var from := Vector3(x, y, front + 12.0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(x, y, front - 2.0), 1))
		if not hit.is_empty():
			fx.call("impact", b, hit.position, Color(1.0, 0.85, 0.5), hit.normal, hit.collider)
			bd.call("bullet", hit, Vector3(0, 0, -1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if mode == "storefront":
		# Bay by bay along the shop windows: two rounds take a pane out, one crazes it; rounds
		# into the piers between leave scars.
		var bays := int(width / pitch)
		for k in bays:
			var x := -width * 0.5 + (k + 0.5) * pitch
			var y := gfh * rng.randf_range(0.35, 0.6)
			var n: int = [2, 1, 0, 2, 1, 2, 0, 1][k % 8]
			for j in n:
				shoot.call(x + rng.randf_range(-0.3, 0.3), y + rng.randf_range(-0.3, 0.3))
			for j in 2:
				shoot.call(-width * 0.5 + (k + 1.0) * pitch + rng.randf_range(-0.12, 0.12), gfh + rng.randf_range(0.2, 1.4))
	elif mode == "office":
		var fl := _env_int("FLOOR", 2)
		var bays := int(width / pitch)
		for k in bays:
			var x := -width * 0.5 + (k + 0.5) * pitch
			var y := gfh + (fl + 0.52) * floor_h
			shoot.call(x, y)
			shoot.call(x + 0.2, y - 0.2)
			if k % 3 != 1:
				shoot.call(x - 0.15, y + floor_h)
	elif mode == "hole":
		ex.call("blast", b, Vector3(width * 0.12, 3.2, front + 0.6), 9.0, 30.0, 0.0)
	for i in _env_int("WAIT", 40):
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "damage_shot.png"
	get_root().get_texture().get_image().save_png(out)
	var key: String = bd.call("key_of", b)
	var dmg: Dictionary = ws.get("building_damage")
	var recs: int = (dmg[key].recs as Array).size() if dmg.has(key) else 0
	if dmg.has(key) and OS.get_environment("DEBUG") == "1":
		for r: Vector4 in dmg[key].recs:
			print("REC kind=", int(r.w / 100.0), " at=", Vector3(r.x, r.y, r.z), " r=", snappedf(fmod(r.w, 100.0), 0.01))
	print("saved ", out, " finish=", b.finish, " style=", b.window_style, " height=", b.height, " records=", recs, " front=", front)
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
