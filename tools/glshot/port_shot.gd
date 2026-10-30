extends SceneTree
## The container terminal's kit on its own (scripts/world/port_kit.gd): a few rows of stacked
## containers in every livery, size and state of wear, a ship-to-shore crane, a yard gantry and
## the quay furniture on a concrete apron, lit with the city's daylight numbers. Seconds a frame
## instead of minutes for a city still, so the look can be iterated.
##
##   OUT=port.png CAM=30,6,40 LOOK=0,3,0 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/port_shot.gd --resolution 1280x720
##
## Env: OUT (png), CAM and LOOK (x,y,z; the yard's rows run along x, the crane stands at
## z -60 with its boom out over +z), FOV (degrees), RAISED=1 stands the crane's boom up,
## LOD=0|1|2 forces one level of every ladder (0 = normal selection), WEAR (0..1, every box),
## HOUR (sun elevation from the hour, 15 by default), SHIP=1 moors the container ship (the
## landmark's own builder) under the boom. Prints each mesh's triangle counts.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
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
	stage.add_child(env)
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 15.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-clampf(90.0 - absf(hour - 12.5) * 11.0, 4.0, 80.0), 35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	stage.add_child(sun)
	# Concrete apron.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.46, 0.45)
	gm.roughness = 0.9
	ground.material_override = gm
	stage.add_child(ground)

	var force_lod := int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else 0
	var wear_env := OS.get_environment("WEAR")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cmesh: ArrayMesh = PortKit.container_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _forced(cmesh, force_lod)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	# Four rows of two-wide stacks along x, every livery in turn, some 20 ft pairs and high-cubes.
	var livery := 0
	for row in 4:
		for col in 5:
			for lane: float in [-1.32, 1.32]:
				var y := 0.0
				var twenty := (row + col) % 3 == 1 and lane > 0.0
				for h in 1 + (row * 7 + col * 3 + int(lane > 0.0)) % 3:
					var hc := (row + col + h) % 2 == 0 and not twenty
					var hgt: float = PortKit.H_HC if hc else PortKit.H_STD
					var n := 2 if twenty else 1
					for k in n:
						var cx := col * 14.0 + (0.0 if n == 1 else (k - 0.5) * (PortKit.L20 + PortKit.PAIR_GAP))
						var look: Array = PortKit.container_look(livery % PortKit.LIVERY_COUNT, rng)
						livery += 1
						var custom: Color = look[1]
						if wear_env != "":
							custom.g = float(wear_env)
						xforms.append(PortKit.container_xform(Vector3(cx, y + hgt * 0.5, row * 9.0 + lane), not twenty, hc, (h + k) % 2 == 1))
						colors.append(look[0])
						customs.append(custom)
					y += hgt
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	var boxes := MultiMeshInstance3D.new()
	boxes.multimesh = mm
	stage.add_child(boxes)
	# A yard gantry over the second row, the crane on the quay behind, bollards on its edge.
	var rtg := MeshInstance3D.new()
	rtg.mesh = _forced(PortKit.rtg_mesh(), force_lod)
	rtg.position = Vector3(28.0, 0.0, 9.0)
	stage.add_child(rtg)
	var crane := MeshInstance3D.new()
	var raised := OS.get_environment("RAISED") == "1"
	crane.mesh = _forced(PortKit.sts_mesh(raised, -9.0 if raised else 40.0, 36.0 if raised else 22.0), force_lod)
	crane.position = Vector3(20.0, 0.0, -60.0)
	stage.add_child(crane)
	if OS.get_environment("SHIP") == "1":
		# The moored ship as the landmark builds it, containers and all, north of the crane.
		(load("res://scripts/world/landmarks.gd") as GDScript).call("_build_cargo_ship", Vector2(40.0, -20.0), stage, null, true)
	for i in 6:
		var b := MeshInstance3D.new()
		b.mesh = PortKit.bollard_mesh()
		b.position = Vector3(-10.0 + i * 16.0, 0.0, -41.0)
		stage.add_child(b)
	for m: Mesh in [cmesh, PortKit.sts_mesh(raised, -9.0 if raised else 40.0, 36.0 if raised else 22.0), PortKit.rtg_mesh()]:
		var surf: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), 0)
		print("mesh: ", (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " triangles, ", (surf.get("lods", []) as Array).size(), " LODs")

	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 2000.0
	stage.add_child(cam)
	var c := _vec(OS.get_environment("CAM"), Vector3(-18.0, 4.0, 30.0))
	var look_at := _vec(OS.get_environment("LOOK"), Vector3(20.0, 3.0, 10.0))
	cam.look_at_from_position(c, look_at, Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "port_shot.png")
	quit()


## `mesh` with only one of its ladder's levels (by rebuilding it from that level's indices), or
## as it is for 0.
static func _forced(mesh: ArrayMesh, lod: int) -> ArrayMesh:
	if lod <= 0:
		return mesh
	var surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var lods: Array = surf.get("lods", [])
	if lods.is_empty():
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	var level: Dictionary = lods[mini(lod, lods.size()) - 1]
	var idx_bytes: PackedByteArray = level.get("index_data", PackedByteArray())
	var idx := PackedInt32Array()
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() <= 65535:
		for i in range(0, idx_bytes.size(), 2):
			idx.append(idx_bytes.decode_u16(i))
	else:
		idx = idx_bytes.to_int32_array()
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mesh.surface_get_material(0))
	return out


static func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
