extends Node3D
## Motorcycle stills in seconds (opengl3 + Xvfb; a scene so the autoloads exist):
##   OUT=/tmp/moto SHOT=lineup VIEWS=side,front3 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/moto/moto_shot.tscn --resolution 1280x720
## SHOT: lineup (the three parked on their stands), riders (each with a traffic rider, `LEAN=`
## rad, `WHEELIE=`, `SPEED=` m/s - 0 puts a boot down), one (`TYPE=0..2` alone; CAM / LOOK / FOV a
## free camera). VIEWS: side, front3, rear3, top, close, low, far. NIGHT=1 lamps lit.
## Writes $OUT_<view>.png.

var bikes: Array = []


func _ready() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if night:
		sm.sky_top_color = Color(0.01, 0.012, 0.02)
		sm.sky_horizon_color = Color(0.04, 0.035, 0.03)
		sm.ground_horizon_color = Color(0.03, 0.025, 0.02)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -125.0, 0.0)
	sun.light_energy = 0.05 if night else 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(300, 2, 300)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	gm.mesh = pm
	gm.material_override = PropFactory.road("asphalt", 4.0, Color(0.85, 0.85, 0.86), 7)
	ground.add_child(gm)
	add_child(ground)
	var shot := OS.get_environment("SHOT")
	if shot == "":
		shot = "lineup"
	var types: Array = [0, 1, 2]
	if shot == "one":
		types = [OS.get_environment("TYPE").to_int()]
	for i in types.size():
		var m := Motorcycle.make(Motorcycle.TYPES[types[i]], 11 + i * 7 + OS.get_environment("LOOK").to_int())
		var x := (float(i) - float(types.size() - 1) * 0.5) * 2.4
		if shot == "riders" or OS.get_environment("RIDER") == "1":
			m.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 8.0, "v": 8.0}
			m.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			m.freeze = true
			m.position = Vector3(x, -float(m._dims().road), 0.0)
			m.hold_pose = {"lean": OS.get_environment("LEAN").to_float(), "wheelie": OS.get_environment("WHEELIE").to_float(),
				"speed": OS.get_environment("SPEED").to_float() if OS.get_environment("SPEED") != "" else 8.0, "steer": 0.0}
			m.traffic_speed = float(m.hold_pose.speed)
		else:
			m.position = Vector3(x, 0.5, 0.0)
		add_child(m)
		bikes.append(m)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = OS.get_environment("FOV").to_float() if OS.get_environment("FOV") != "" else 34.0
	# Let the parked ones settle on their springs and the riders take their pose.
	for k in 90:
		await get_tree().physics_frame
	for b in bikes:
		var r = b.get("_rider")
		if r != null and is_instance_valid(r):
			var meshes: Array = r.find_children("*", "MeshInstance3D", true, false)
			var vis := 0
			for mm in meshes:
				if (mm as MeshInstance3D).is_visible_in_tree():
					vis += 1
			print("RIDER %s at %s meshes %d visible %d down %s inside %s" % [b.display_name(), str(r.global_position), meshes.size(), vis, r._down, r.is_inside_tree()])
		else:
			print("RIDER none on ", b.display_name())
	var out := OS.get_environment("OUT")
	if out == "":
		out = "/tmp/moto"
	var views := OS.get_environment("VIEWS")
	if views == "":
		views = "side"
	var w := float(types.size() - 1) * 1.2 + 1.5
	for v in views.split(","):
		var at := Vector3.ZERO
		var look := Vector3(0.0, 0.65, 0.0)
		match v:
			"side": at = Vector3(6.5 + w * 1.6, 1.0, 0.4)
			"left": at = Vector3(-6.5 - w * 1.6, 1.0, -0.4)
			"front3": at = Vector3(3.2 + w, 1.5, -5.5 - w)
			"rear3": at = Vector3(-3.0 - w, 1.7, 5.5 + w)
			"top": at = Vector3(2.0, 6.0 + w * 2.0, 3.0)
			"low": at = Vector3(2.4, 0.35, -3.4)
			"close": at = Vector3(1.6, 1.25, -1.4)
			"far": at = Vector3(30.0, 6.0, -30.0)
			_: pass
		if OS.get_environment("CAM") != "":
			var c := OS.get_environment("CAM").split(",")
			at = Vector3(c[0].to_float(), c[1].to_float(), c[2].to_float())
		if OS.get_environment("LOOK_AT") != "":
			var c := OS.get_environment("LOOK_AT").split(",")
			look = Vector3(c[0].to_float(), c[1].to_float(), c[2].to_float())
		cam.global_position = at
		cam.look_at(look)
		for k in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [out, v])
		print("wrote %s_%s.png" % [out, v])
	get_tree().quit()
