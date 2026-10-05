extends SceneTree
## The marketplace lane's puestos on their own (PuebloMarket): one stall of each kind of goods in a
## row on a brick floor, daylight or night. Seconds a frame instead of minutes for a city still.
##
##   OUT=s.png CAM=0,1.6,4 LOOK=0,1.3,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/pueblo_lane/stall_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, DEBUG=n (pueblo_market's debug_mode: 1 the UV, 2 the
## kind, 3 the seed). The stalls face +Z, 2.6 m apart along x from x 0 (sarapes, pottery, pinatas,
## hats, dresses, candy, silver, leather).
func _initialize() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) if not night else Color(0.05, 0.04, 0.04)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45 if not night else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25 if not night else 1.6
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(40.0, 0.1, 12.0)
	floor_mi.mesh = fb
	floor_mi.position = Vector3(8.0, -0.05, 0.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.3, 0.24)
	floor_mi.material_override = fm
	stage.add_child(floor_mi)
	var pm: GDScript = load("res://scripts/world/pueblo_market.gd")
	var solid: Object = pm.Acc.new()
	var thin: Object = pm.Acc.new()
	var small: Object = pm.Acc.new()
	for k in 8:
		pm.call("stall", solid, thin, Transform3D(Basis(), Vector3(2.6 * float(k), 0.0, 0.0)), k, 9001 + k, 0, small)
	var dbg := int(OS.get_environment("DEBUG")) if OS.get_environment("DEBUG") != "" else 0
	for pair: Array in [[solid, pm.call("solid_material")], [small, pm.call("solid_material")], [thin, pm.call("thin_material")]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].call("mesh", pair[1])
		(pair[1] as ShaderMaterial).set_shader_parameter("debug_mode", dbg)
		stage.add_child(mi)
	print("tris solid %d small %d thin %d" % [solid.call("tris"), small.call("tris"), thin.call("tris")])
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	stage.add_child(cam)
	var c := _v(OS.get_environment("CAM"), Vector3(0.0, 1.6, 4.0))
	var l := _v(OS.get_environment("LOOK"), Vector3(0.0, 1.3, 0.0))
	cam.look_at_from_position(c, l)
	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "stall.png"
	img.save_png(out)
	print("saved ", out)
	quit()


func _v(s: String, d: Vector3) -> Vector3:
	if s == "":
		return d
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
