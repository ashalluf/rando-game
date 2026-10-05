extends SceneTree
## The LOD line, side by side: a row of seeded buildings rendered twice from the same camera -
## once as the near Building (its walls, kit and roof plant) and once as the far boxes the LOD
## chunks and the far city draw for it (FarBuilding on building_lod.gdshader) - saved as
## <OUT>_near.png and <OUT>_far.png, with a mask of each building (<OUT>_mask.png, building i
## painted in grey (i + 1) * 20) so tools/glshot/far_pair.py can compare them building by building.
## It also proves the far shader compiles: a shader error falls back to blank white.
##
##   OUT=pair LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/far_building_shot.gd --resolution 960x540
##
## Env: OUT (path stem), DIST (metres from the row, default 200: the FULL -> LOD handoff), NIGHT=1
## (21:00: lamps and lit windows), HEIGHT (camera height, default 1/3 of the tallest), N (buildings,
## default 6), SEED0 (first seed), DOWNTOWN=1 (tall towers on podium lots: lot fill, parking decks).
## CHAMFER=1 cuts every building's corners (Building.chamfer_chance; 0 none), FAR_CORNERS=0 the
## far boxes' old painted piers.
## The light is a fixed sun and sky, not DayNight: judge the two frames against each other.

const FINISHES := [0, 1, 2, 3, 0, 3, 1, 2]


func _initialize() -> void:
	# The autoloads exist only after the first frames, and the Building chain compiles against them.
	for i in 3:
		await process_frame
	var night := OS.get_environment("NIGHT") == "1"
	var nf := 1.0 if night else 0.0
	RenderingServer.global_shader_parameter_set("night_factor", nf)
	RenderingServer.global_shader_parameter_set("lamp_factor", nf)
	var sun_dir := Vector3(-0.45, 0.70, 0.55).normalized()
	RenderingServer.global_shader_parameter_set("sun_direction", sun_dir)
	var sky := Color(0.03, 0.035, 0.06) if night else Color(0.52, 0.66, 0.86)
	RenderingServer.global_shader_parameter_set("sky_tint", sky)
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.10, 0.11, 0.16) if night else Color(0.55, 0.62, 0.72)
	e.ambient_light_energy = 0.4 if night else 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	sun.light_energy = 0.08 if night else 1.3
	root3d.add_child(sun)

	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var far_building: GDScript = load("res://scripts/world/far_building.gd")
	var factory: GDScript = load("res://scripts/world/prop_factory.gd")
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var seed0 := int(OS.get_environment("SEED0")) if OS.get_environment("SEED0") != "" else 101
	var downtown := OS.get_environment("DOWNTOWN") == "1"
	var near_root := Node3D.new()
	root3d.add_child(near_root)
	var xforms: Array = []
	var colors: Array = []
	var customs: Array = []
	var x := 0.0
	var tallest := 0.0
	var spans: Array = []
	for i in n:
		var lot := Vector2(34.0, 30.0) if downtown else Vector2(26.0, 24.0)
		var near = scene.instantiate()
		var far = scene.instantiate()
		for b in [near, far]:
			b.seed = seed0 + i * 37
			b.lot_size = lot
			b.min_height = 70.0 if downtown else 14.0 + 6.0 * float(i % 4)
			b.max_height = 120.0 if downtown else 22.0 + 8.0 * float(i % 4)
			b.finish_options.assign([FINISHES[i % FINISHES.size()]])
			b.podium_lot = downtown
			b.plinth_depth = 0.75
			if OS.get_environment("CHAMFER") != "":
				b.chamfer_chance = float(OS.get_environment("CHAMFER"))
			b.position = Vector3(x + lot.x * 0.5, 0.0, 0.0)
		near_root.add_child(near)
		var style: Dictionary = far.plan_only()
		for fb: Array in far_building.boxes(far, style, far.plinth_depth):
			var xf: Transform3D = fb[0]
			xforms.append(Transform3D(xf.basis, xf.origin + far.position))
			colors.append(fb[1])
			customs.append(fb[2])
		tallest = maxf(tallest, near.height)
		spans.append([x, x + lot.x])
		far.free()
		x += lot.x + 8.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = factory.unit_box()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	var far_node := MultiMeshInstance3D.new()
	far_node.multimesh = mm
	far_node.material_override = factory.building_lod_material()
	root3d.add_child(far_node)
	# A ground under both.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.32, 0.33)
	ground.material_override = gm
	ground.position = Vector3(x * 0.5, -0.02, 0.0)
	root3d.add_child(ground)

	var cam := Camera3D.new()
	root3d.add_child(cam)
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 200.0
	var hgt := float(OS.get_environment("HEIGHT")) if OS.get_environment("HEIGHT") != "" else tallest / 3.0
	var mid := Vector3(x * 0.5 - 4.0, tallest * 0.45, 0.0)
	cam.fov = 2.0 * rad_to_deg(atan((x * 0.55) / dist)) if x * 0.55 / dist > tan(deg_to_rad(20.0)) else 40.0
	cam.far = 8000.0
	cam.look_at_from_position(Vector3(mid.x - dist * 0.42, hgt, dist), mid, Vector3.UP)
	cam.make_current()
	var out := OS.get_environment("OUT")
	if out == "":
		out = "far_pair"
	# The near frame (far boxes hidden), then the far frame (near buildings hidden).
	far_node.visible = false
	for i in 8:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "_near.png")
	near_root.visible = false
	far_node.visible = true
	ground.visible = true
	for i in 8:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "_far.png")
	# The mask: each building's far boxes in its own flat grey, nothing else.
	var mask_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, skip_vertex_transform;\nvoid vertex() {\n\tvec3 s = vec3(MODEL_MATRIX[0][0], MODEL_MATRIX[1][1], MODEL_MATRIX[2][2]);\n\tvec3 w = INSTANCE_CUSTOM.a < -0.5 ? MODEL_MATRIX[3].xyz + VERTEX * s : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n\tVERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;\n\tCOLOR = vec4(COLOR.rgb, 1.0);\n}\nvoid fragment() {\n\tALBEDO = COLOR.rgb;\n}\n"
	mask_mat.shader = sh
	var mask_colors: Array = []
	for i in xforms.size():
		var px: float = (xforms[i] as Transform3D).origin.x
		var k := 0
		for j in spans.size():
			if px >= float(spans[j][0]) - 0.5 and px <= float(spans[j][1]) + 0.5:
				k = j
		var g := float(k + 1) * 20.0 / 255.0
		mm.set_instance_color(i, Color(g, g, g, 1.0))
	far_node.material_override = mask_mat
	ground.visible = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.background_color = Color.BLACK
	sun.visible = false
	e.ambient_light_energy = 0.0
	for i in 4:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "_mask.png")
	print("FAR_PAIR saved %s_near/_far/_mask.png: %d buildings, %d far boxes, renderer %s" % [out, n, xforms.size(), RenderingServer.get_current_rendering_method()])
	quit()
