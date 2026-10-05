extends SceneTree
## The city's birds alone on a pavement, lit with the city's daylight numbers: a lineup of every
## species in its poses (standing, pecking, mid-stride, wings down, wings up, gliding) for
## judging BirdMesh / bird.gdshader in seconds, without the city.
##
##   OUT=birds.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/bird_shot.gd --resolution 1280x720
##
## Env: OUT (png), SPECIES (comma list, default pigeon,gull,crow,sparrow), LOD (0 near, 1 mid,
## 2 far), CAM / LOOK (x,y,z; default a low three-quarter view down the row), FOV, MORPHS=1 (a
## row of pigeon colour morphs instead of poses), SCALE (multiplies every bird, to read the far
## LODs up close), TRIS=1 prints each mesh's triangle count. ONLY=<pose index> draws that one
## pose alone at the origin (a close-up: CAM / LOOK in metres round it, e.g. CAM=0.5,0.25,-0.6
## LOOK=0,0.12,0 for a standing pigeon at a metre).
const POSES := [
	# [label, spread, phase, peck, walk, flap amplitude]
	["stand", 0.0, 0.0, 0.0, 0.0, 0.0],
	["peck", 0.0, 0.0, 0.85, 0.0, 0.0],
	["stride", 0.0, 0.2, 0.0, 1.0, 0.0],
	["down", 1.0, 0.25, 0.0, 0.0, 1.0],
	["up", 1.0, 0.72, 0.0, 0.0, 1.0],
	["glide", 1.0, 0.0, 0.0, 0.0, 0.0],
]
const MORPH_TINTS := [Color(0, 0, 0), Color(0.9, 0.9, 0.88), Color(0.16, 0.16, 0.19), Color(0.52, 0.35, 0.27), Color(0.42, 0.44, 0.5), Color(0, 0, 0)]


var _first_size := 0.0


func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.58)
	sky_mat.sky_horizon_color = Color(0.72, 0.70, 0.66)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.45, 0.43)
	gm.roughness = 0.9
	ground.material_override = gm
	stage.add_child(ground)
	var lod := int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else 0
	var names := (OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "pigeon,gull,crow,sparrow").split(",")
	var morphs := OS.get_environment("MORPHS") == "1"
	var scale := float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 1.0
	var row_z := 0.0
	for name in names:
		var mesh := BirdMesh.mesh(name, lod)
		if OS.get_environment("TRIS") == "1":
			print("TRIS %s lod %d: %d" % [name, lod, mesh.surface_get_array_index_len(0) / 3])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = POSES.size()
		var size: float = mesh.get_aabb().size.z * scale
		if _first_size == 0.0:
			_first_size = size
		var only := int(OS.get_environment("ONLY")) if OS.get_environment("ONLY") != "" else -1
		for i in POSES.size():
			var p: Array = POSES[i]
			var x := (float(i) - 2.5) * size * 1.6
			if only >= 0:
				# Every pose at the origin, all but the chosen one shrunk to nothing.
				x = 0.0
				if i != only:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -1, 0)))
					continue
			var lift := 0.0 if float(p[1]) < 0.5 else size * 0.9
			var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else -60.0
			var b := Basis(Vector3.UP, deg_to_rad(yaw)).scaled(Vector3.ONE * scale)
			mm.set_instance_transform(i, Transform3D(b, Vector3(x, lift, row_z)))
			var tint: Color = MORPH_TINTS[i] if morphs else Color(0, 0, 0)
			mm.set_instance_color(i, Color(tint.r, tint.g, tint.b, 0.0 if morphs else float(p[5])))
			if morphs:
				mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
			else:
				mm.set_instance_custom_data(i, Color(float(p[1]), float(p[2]), float(p[3]), float(p[4])))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = BirdMesh.material(name)
		stage.add_child(mi)
		row_z += size * 1.8
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 35.0
	cam.near = 0.01
	stage.add_child(cam)
	var width := float(POSES.size()) * _first_size * 1.6
	var mid := Vector3(0.0, _first_size * 0.35, row_z * 0.5 - _first_size * 0.9)
	var cam_at := _vec(OS.get_environment("CAM"), mid + Vector3(0.0, width * 0.32, -width * 1.15))
	var look := _vec(OS.get_environment("LOOK"), mid)
	cam.look_at_from_position(cam_at, look)
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "birds.png"
	img.save_png(out)
	print("saved ", out)
	quit()


func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
