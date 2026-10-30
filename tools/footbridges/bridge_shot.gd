extends Node3D
## One footbridge on its own (FootbridgeKit), seconds a frame: the real plan's bridge, a grey ground
## at its feet, the road or a stand-in deck under it, the city's AgX and a sun. For iterating on the
## kit's look; judge it in the city with tools/glshot/still_shot.gd EYE= (the probe prints EYEs).
##
##   ID=fb_f_1_5 OUT=b.png CAM=-30,8,25 LOOK=0,6,0 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . res://tools/footbridges/bridge_shot.tscn --resolution 1280x720
##
## Env: ID (a probe id; else KIND=0|1 the first of that kind round AT), CAM / LOOK (metres from the
## span's centre, at its ground), FOV, HOUR, LOD=1 (Detail.LOD), NIGHT=1 (lamp_factor 1, dark sky),
## SHOTS="cam;look|cam;look|..." several views (OUT gets _0, _1, ...).
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var at := Vector2(1500.0, 800.0)
	var all := Footbridges.near(plan, Rect2(at - Vector2.ONE * 3500.0, Vector2.ONE * 7000.0))
	var want := OS.get_environment("ID")
	var kind := int(OS.get_environment("KIND")) if OS.get_environment("KIND") != "" else 1
	var b: Dictionary = {}
	for x: Dictionary in all:
		if (want != "" and x.id == want) or (want == "" and int(x.kind) == kind):
			b = x
			break
	if b.is_empty():
		print("no bridge")
		get_tree().quit()
		return
	var night := OS.get_environment("NIGHT") == "1"
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var c: Vector2 = b.c
	var g: float = (b.ends[0] as Dictionary).ground
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) * (0.05 if night else 1.0)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) * (0.05 if night else 1.0)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45) * (0.05 if night else 1.0)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18) * (0.05 if night else 1.0)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	env.environment = e
	add_child(env)
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 15.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-clampf(90.0 - absf(hour - 12.5) * 11.0, 4.0, 80.0), 35.0, 0.0)
	sun.light_energy = 0.05 if night else 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	var origin := Vector3(c.x, g, c.y)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.5, 0.48)
	gm.roughness = 0.9
	ground.material_override = gm
	ground.position = Vector3(c.x, g - 0.02, c.y)
	add_child(ground)
	# The road or the deck under the span.
	var dir: Vector2 = b.dir
	var along: Vector2 = b.along
	var under := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var um := StandardMaterial3D.new()
	um.albedo_color = Color(0.2, 0.2, 0.21)
	if int(b.kind) == Footbridges.Kind.FREEWAY:
		var deck: float = b.deck
		bm.size = Vector3(34.0, 1.4, 300.0)
		under.position = Vector3(c.x, deck - 0.7, c.y)
	else:
		bm.size = Vector3(plan.road_width(int(b.axis), int(b.index)), 0.1, 300.0)
		under.position = Vector3(c.x, float(b.road_top) - 0.05, c.y)
	under.mesh = bm
	under.material_override = um
	under.basis = Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(along.x, 0, along.y))
	add_child(under)
	var lod := OS.get_environment("LOD") == "1"
	var boxes: Array = []
	var geo := FootbridgeKit.build(b, Vector3(c.x, 0.0, c.y), FootbridgeKit.Detail.LOD if lod else FootbridgeKit.Detail.FULL, boxes)
	var pivot := Node3D.new()
	pivot.position = Vector3(c.x, 0.0, c.y)
	add_child(pivot)
	var tris := geo.triangles
	geo.commit(pivot, "Mesh")
	print("bridge %s kind=%d form=%d triangles=%d boxes=%d y=%.2f g=%.2f" % [b.id, b.kind, b.form, tris, boxes.size(), b.y, g])
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0
	cam.far = 2000.0
	add_child(cam)
	var shots := OS.get_environment("SHOTS")
	if shots == "":
		shots = "%s;%s" % [OS.get_environment("CAM") if OS.get_environment("CAM") != "" else "-30,8,25", OS.get_environment("LOOK") if OS.get_environment("LOOK") != "" else "0,6,0"]
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "bridge.png"
	var list := shots.split("|")
	for si in list.size():
		var parts := list[si].split(";")
		var cp := parts[0].split(",")
		var lp := parts[1].split(",")
		# CAM / LOOK are in the bridge's frame: x across the span (along the road), z along it.
		var cv := Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
		var lv := Vector3(float(lp[0]), float(lp[1]), float(lp[2]))
		var fr := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(dir.x, 0, dir.y))
		cam.global_position = origin + fr * cv
		cam.look_at(origin + fr * lv, Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := out if list.size() == 1 else out.replace(".png", "_%d.png" % si)
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()
