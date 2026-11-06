extends Node3D
## The club front alone (rc5-club-line; seconds, opengl3 + Xvfb): a wall, a club entrance with its
## rope line and sign, two searchlight carts with their beams (SkyBeam), lit as at 23:30, seen from
## across a 20 m street like the club_line refcam.
##   OUT=club.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . tools/rc5_club_line/club_shot.tscn
## T=seconds the beams' clock; LED=0..3 the club's colour; DIST=metres across (30); FOV (50);
## PITCH (10). RC5_CLUB_LINE=0 the old look.

func _ready() -> void:
	await get_tree().process_frame
	var kit: GDScript = load("res://scripts/world/nightlife_kit.gd")
	var root3 := Node3D.new()
	add_child(root3)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	(load("res://scripts/world/day_night.gd") as GDScript).set("lamp_now", 1.0)
	(load("res://scripts/world/rain_day.gd") as GDScript).set("night_lamp", 1.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.13, 0.18)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 40, 0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.7, 0.8, 1.0)
	root3.add_child(moon)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.31)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	floor_mi.material_override = fm
	root3.add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 20, 0.4)
	wall.mesh = bm
	wall.position = Vector3(0, 10, -0.2)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.42, 0.38)
	wall.material_override = wm
	root3.add_child(wall)
	var led := int(OS.get_environment("LED")) if OS.get_environment("LED") != "" else 0
	var custom := Color(0.06, 0.09, 0.26, 0.6)
	var items := [[kit.call("club_entrance", led), Vector3(0, 0, 0)], [kit.call("rope_line", 8, -1, 0), Vector3(0, 0, 0)],
		[kit.call("searchlight_cart"), Vector3(-3.4, 0, 6.05)], [kit.call("searchlight_cart"), Vector3(3.4, 0, 6.05)]]
	var rc: GDScript = load("res://scripts/world/rc5_club_line.gd")
	if rc.get("enabled"):
		items.append([rc.call("board", 5.2, led), Vector3(0, 0, 0)])
		var nm := MeshInstance3D.new()
		nm.mesh = PropFactory.text_mesh("AFTERGLOW", rc.get("NAME_H"))
		nm.material_override = kit.call("sign_material", (kit.get("LED_COLORS")[led] as Color).srgb_to_linear())
		nm.position = Vector3(0, ((rc.get("BOARD_Y") as Vector2).x + (rc.get("BOARD_Y") as Vector2).y) * 0.5, rc.get("BOARD_D") + 0.012)
		root3.add_child(nm)
	for it: Array in items:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = it[0]
		mm.instance_count = 1
		var b := Basis()
		if (it[1] as Vector3).z > 1.0:
			b = Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT)
		mm.set_instance_transform(0, Transform3D(b, it[1]))
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, custom)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root3.add_child(mmi)
	var sl: GDScript = load("res://scripts/world/sky_beam.gd")
	for i in 2:
		var beam: Node3D = sl.new()
		beam.set("seed_value", 1234 + i * 77)
		beam.position = Vector3(-3.4 + 6.8 * i, kit.get("YOKE_Y"), 6.05 + 0.35)
		beam.basis = Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT)
		root3.add_child(beam)
	var nl: GDScript = load("res://scripts/world/nightlife.gd")
	var sign_mi := MeshInstance3D.new()
	sign_mi.mesh = PropFactory.text_mesh("AFTERGLOW", 0.26)
	sign_mi.material_override = kit.call("sign_material", (kit.get("LED_COLORS")[led] as Color).srgb_to_linear())
	sign_mi.position = Vector3(0, 3.05 + 0.17, 2.512)
	root3.add_child(sign_mi)
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 30.0
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 3000.0
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else 10.0
	cam.position = Vector3(8.0, 1.7, dist)
	cam.rotation_degrees = Vector3(pitch, 15.0, 0.0)
	root3.add_child(cam)
	cam.make_current()
	var t := float(OS.get_environment("T")) if OS.get_environment("T") != "" else 3.0
	for i in 12:
		await get_tree().process_frame
		for n in root3.get_children():
			if n.has_method("pose"):
				n.call("pose", t)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "club.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
