extends SceneTree
## The code-built Los Angeles trees and accents (scripts/world/la_trees.gd) in a row on a lawn,
## with a palm and a scanned street tree for scale. Seconds a frame instead of minutes for a city
## still, and the triangle count of every level printed.
##
##   OUT=t.png xvfb-run -a -s "-screen 0 1600x700x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/glshot/la_tree_shot.gd --resolution 1600x700
##
## Env: OUT, SPECIES=0,1,... (LaTrees.Species; default all), VARIANT=n (default both), LEVEL=n
## (draw that ladder level as the mesh, -1 the ladder), CAM / LOOK (x,y,z), FOV, NIGHT=1,
## COMPARE=0 drops the palm and the scanned tree, GAP=metres between trees, SUN=pitch,yaw.
func _initialize() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.45, 0.7) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8) if not night else Color(0.05, 0.04, 0.04)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("wind_factor", 0.3)
	var sun := DirectionalLight3D.new()
	var sp_env := OS.get_environment("SUN")
	var sun_rot := Vector2(-48.0, 30.0)
	if sp_env != "":
		var q := sp_env.split(",")
		sun_rot = Vector2(q[0].to_float(), q[1].to_float())
	sun.rotation_degrees = Vector3(sun_rot.x, sun_rot.y, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	stage.add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.transform.basis.z)
	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(400.0, 0.1, 200.0)
	ground.mesh = gb
	ground.position = Vector3(0.0, -0.05, 0.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.26, 0.12)
	gm.roughness = 0.95
	ground.material_override = gm
	stage.add_child(ground)
	var la: GDScript = load("res://scripts/world/la_trees.gd")
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	var species: Array = []
	var s_env := OS.get_environment("SPECIES")
	if s_env != "":
		for p in s_env.split(","):
			species.append(p.to_int())
	else:
		for i in (la.get("NAMES") as Array).size():
			species.append(i)
	var variants: Array = [0, 1]
	if OS.get_environment("VARIANT") != "":
		variants = [OS.get_environment("VARIANT").to_int()]
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else -1
	var heights: Array = la.get("HEIGHT")
	var names: Array = la.get("NAMES")
	var x := 0.0
	var gap := float(OS.get_environment("GAP")) if OS.get_environment("GAP") != "" else 0.0
	var placed: Array = []
	if OS.get_environment("COMPARE") != "0":
		placed.append([pf.call("palm", 0), "palm_0", 6.0])
		placed.append([pf.call("model_tree", 0), "tree_a", 7.0])
	for sp: int in species:
		for v: int in variants:
			var t0 := Time.get_ticks_msec()
			var m: Mesh = la.call("mesh", sp, v)
			var ms := Time.get_ticks_msec() - t0
			var arrs: Array = la.call("level_arrays", sp, v)
			var edges: Array = la.call("level_edges", sp, v)
			var line := "%s_%d built %d ms, levels:" % [names[sp], v, ms]
			for l in arrs.size():
				line += " L%d %d tris (edge %.2f)" % [l, (arrs[l][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, edges[l]]
			print(line)
			if level >= 0:
				var lm := ArrayMesh.new()
				lm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs[level])
				lm.surface_set_material(0, la.call("material", sp))
				m = lm
			var cr: Dictionary = la.call("crown", sp, v)
			var w: float = maxf((cr.radii as Vector3).x * 2.0, 1.2) + 0.8
			placed.append([m, "%s_%d" % [names[sp], v], w])
	var total := 0.0
	for p: Array in placed:
		total += float(p[2]) + gap
	x = -total * 0.5
	for p: Array in placed:
		x += (float(p[2]) + gap) * 0.5
		_place(stage, p[0], Transform3D(Basis(), Vector3(x, 0.0, 0.0)))
		x += (float(p[2]) + gap) * 0.5
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 2000.0
	stage.add_child(cam)
	var top := 2.0
	for sp: int in species:
		top = maxf(top, float(heights[sp]))
	var def_cam := Vector3(0.0, top * 0.4, maxf(total * 0.62, top * 1.5) + 4.0)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), def_cam), _vec(OS.get_environment("LOOK"), Vector3(0.0, top * 0.45, 0.0)), Vector3.UP)
	cam.make_current()
	for i in 10:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "la_tree_shot.png")
	quit()


func _place(stage: Node3D, mesh: Mesh, xf: Transform3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(0.5, 0.5, 0.5, 0.6))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stage.add_child(mmi)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
