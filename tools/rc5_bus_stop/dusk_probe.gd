extends SceneTree
## The rainy dusk's numbers without a city (rc5-bus-stop-rain): the city's Environment and DayNight
## (tools/sky/sky_shot.gd's set-up) at HOURS with weather_darken DARK (0.5 = rain, 0.72 storm),
## printing the sun, the cloud colour, the sky, the fog, the ambient and the grade's weights.
##   DARK=0.5 HOURS=17,17.5,18,18.5,19 godot --headless --path . --script tools/rc5_bus_stop/dusk_probe.gd
## RC5_BUS_STOP=0 for the A/B. With a renderer and OUT=dir it also saves a sky still per hour
## (looking west, YAW 90 default... the game's yaw).

func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _initialize() -> void:
	var ps := load("res://scenes/levels/city.tscn") as PackedScene
	var st := ps.get_state()
	var env: Environment
	for i in st.get_node_count():
		if st.get_node_type(i) == "WorldEnvironment":
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == "environment":
					env = st.get_node_property_value(i, k)
	env = env.duplicate(true) as Environment
	var top := Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	top.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000, 60000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.15, 0.13)
	ground.material_override = gm
	top.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 12000.0
	cam.position = Vector3(0, 2, 0)
	cam.rotation_degrees = Vector3(float(_env("PITCH", "8")), float(_env("YAW", "90")), 0)
	top.add_child(cam)
	var day: Node = (load("res://scripts/world/day_night.gd") as GDScript).new()
	day.name = "DayNight"
	day.set("sun_path", NodePath("../Sun"))
	day.set("environment_path", NodePath("../Env"))
	top.add_child(day)
	root.add_child(top)
	cam.make_current()
	await process_frame
	var dark := float(_env("DARK", "0.5"))
	var out := _env("OUT", "")
	for hs in _env("HOURS", "17,17.5,18,18.5,19").split(","):
		day.set("hour", float(hs))
		day.set("weather_darken", dark)
		day.set("cloud_extra", 0.5)
		day.call("_apply")
		var sky := env.sky.sky_material as ShaderMaterial
		var grade: Variant = day.get("grade")
		print("DUSK %s dark %.2f sun %s x%.3f cloud %s top %s horizon %s fog %s amb %.3f exposure %.3f golden %.2f" % [hs, dark,
			_c(sun.light_color), sun.light_energy, _c(sky.get_shader_parameter("cloud_color")), _c(sky.get_shader_parameter("sky_top")),
			_c(sky.get_shader_parameter("sky_horizon")), _c(env.fog_light_color), env.ambient_light_energy, env.tonemap_exposure,
			float(day.get("golden"))])
		if out != "":
			for i in 8:
				await process_frame
				day.set("hour", float(hs))
				day.set("weather_darken", dark)
				day.call("_apply")
			root.get_texture().get_image().save_png(out.path_join("dusk_%s.png" % hs))
	quit()


func _c(v: Variant) -> String:
	if v is Color:
		var c: Color = v
		return "(%.3f %.3f %.3f)" % [c.r, c.g, c.b]
	if v is Vector3:
		var w: Vector3 = v
		return "(%.3f %.3f %.3f)" % [w.x, w.y, w.z]
	return str(v)
