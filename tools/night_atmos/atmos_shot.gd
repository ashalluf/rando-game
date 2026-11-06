extends SceneTree
## The night air alone (NightAtmos), small enough for Forward+ under lavapipe: a wet street of
## sodium and LED lamps (pole, head, OmniLight, halo and shaft instances), cars' lamp meshes
## coming and going, under the city scene's own Environment. Seconds on opengl3, a few minutes on
## lavapipe (the city, and now even block_shot, no longer fit there):
##
##   OUT=/tmp/a.png HAZE=0.9 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/night_atmos/atmos_shot.gd \
##     --resolution 960x540
##
## Env: OUT, HAZE (0..1), VOL (1: the Environment's volumetric fog on, which turns the drawn shafts
## off as the game does; default 0), ATMOS=0 (no halos, shafts or car halos: the before), FRAMES.

var _frames := 0
var _cam: Camera3D
var _want := 8


func _initialize() -> void:
	var atmos := OS.get_environment("ATMOS") != "0"
	var na: GDScript = load("res://scripts/world/night_atmos.gd")
	na.set("enabled", atmos)
	var haze := float(OS.get_environment("HAZE")) if OS.get_environment("HAZE") != "" else 0.85
	var vol := OS.get_environment("VOL") == "1"
	_want = int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 8
	var root3 := Node3D.new()
	root.add_child(root3)
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var env: Environment = (city.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate()
	city.free()
	env.volumetric_fog_enabled = vol
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_energy = 0.4
	env.fog_light_color = Color(0.08, 0.08, 0.1).lerp(Color(0.62, 0.36, 0.14), 0.42 * haze if atmos else 0.0)
	env.fog_density = 0.004 * haze
	env.tonemap_exposure = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	for g: Array in [["lamp_factor", 1.0], ["night_factor", 1.0], ["road_wetness", 0.8], ["rain_intensity", 0.6 if haze > 0.7 else 0.0]]:
		RenderingServer.global_shader_parameter_set(g[0], g[1])
	RenderingServer.global_shader_parameter_set("night_atmos", Vector4(haze, 0.0 if vol else 1.0, 1.0 if atmos else 0.0, 540.0))
	# The street: dark wet asphalt and two pavements.
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 240.0)
	road.mesh = pm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.05, 0.05, 0.055)
	rm.roughness = 0.18
	road.material_override = rm
	road.position = Vector3(0.0, 0.0, -100.0)
	root3.add_child(road)
	var walls := StandardMaterial3D.new()
	walls.albedo_color = Color(0.25, 0.22, 0.2)
	for side: float in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 40.0, 240.0)
		b.mesh = bm
		b.material_override = walls
		b.position = Vector3(side * 16.0, 20.0, -100.0)
		root3.add_child(b)
	# Lamps every 24 m both sides, sodium on the left, LED on the right.
	var halos := MultiMesh.new()
	halos.transform_format = MultiMesh.TRANSFORM_3D
	halos.use_colors = true
	halos.use_custom_data = true
	halos.mesh = na.call("halo_mesh")
	var shafts := MultiMesh.new()
	shafts.transform_format = MultiMesh.TRANSFORM_3D
	shafts.use_colors = true
	shafts.use_custom_data = true
	shafts.mesh = na.call("shaft_mesh")
	var parts: Array = []
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.2, 0.2, 0.22)
	for i in 8:
		for side: float in [-1.0, 1.0]:
			var at := Vector3(side * 12.5, 0.0, -6.0 - 24.0 * i - (12.0 if side > 0.0 else 0.0))
			var head := at + Vector3(-side * 1.6, 8.0, 0.0)
			var p := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.13
			cm.height = 8.0
			p.mesh = cm
			p.material_override = pole
			p.position = at + Vector3(0.0, 4.0, 0.0)
			root3.add_child(p)
			var hm := MeshInstance3D.new()
			var hb := BoxMesh.new()
			hb.size = Vector3(0.7, 0.18, 0.35)
			hm.mesh = hb
			var lens := StandardMaterial3D.new()
			lens.emission_enabled = true
			lens.emission = Color(1.0, 0.7, 0.35) if side < 0.0 else Color(0.85, 0.92, 1.0)
			lens.emission_energy_multiplier = 6.0
			hm.material_override = lens
			hm.position = head
			root3.add_child(hm)
			var l := OmniLight3D.new()
			l.position = head + Vector3(0.0, -0.3, 0.0)
			l.light_color = Color(1.0, 0.75, 0.45) if side < 0.0 else Color(0.86, 0.92, 1.0)
			l.light_energy = 2.2
			l.omni_range = 16.0
			l.omni_attenuation = 1.2
			root3.add_child(l)
			var world_xz := Vector2(-3000.0, -3000.0) if side < 0.0 else Vector2(1.0e5, 1.0e5)
			parts.append_array(na.call("lamp_parts", [head], head, 0.0, 12.0, world_xz, true))
	var hx: Array = []
	var sx: Array = []
	for pp: Array in parts:
		(hx if pp[0] == na.get("HALO_KEY") else sx).append(pp)
	for pair: Array in [[halos, hx], [shafts, sx]]:
		var mm: MultiMesh = pair[0]
		var list: Array = pair[1]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k][2])
			mm.set_instance_color(k, list[k][3])
			mm.set_instance_custom_data(k, list[k][4])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root3.add_child(node)
	# Cars: two coming (head lamps), two going (tail lamps, one braking).
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.12, 0.13, 0.16)
	body.metallic = 0.6
	body.roughness = 0.25
	for c: Array in [[Vector3(-4.0, 0.0, -38.0), 0.0, false], [Vector3(-4.5, 0.0, -90.0), 0.0, false], [Vector3(4.0, 0.0, -30.0), PI, true], [Vector3(4.0, 0.0, -70.0), PI, false]]:
		var car := Node3D.new()
		car.position = c[0]
		car.rotation.y = PI - float(c[1])
		root3.add_child(car)
		var cb := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(1.85, 1.3, 4.6)
		cb.mesh = cbm
		cb.material_override = body
		cb.position = Vector3(0.0, 0.85, 0.0)
		car.add_child(cb)
		var lights := MeshInstance3D.new()
		lights.mesh = pf.call("vehicle_lights", 1.85, 4.6, 0.75, -0.0)
		lights.material_override = pf.call("vehicle_light_material", bool(c[2]))
		car.add_child(lights)
	_cam = Camera3D.new()
	_cam.position = Vector3(-1.5, 1.7, 10.0)
	_cam.rotation_degrees = Vector3(3.0, -4.0, 0.0)
	_cam.fov = 60.0
	_cam.far = 2000.0
	root3.add_child(_cam)
	_cam.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == _want:
		var img := root.get_viewport().get_texture().get_image()
		var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/atmos.png"
		img.save_png(out)
		print("ATMOS_SHOT saved ", out)
		return true
	return false
