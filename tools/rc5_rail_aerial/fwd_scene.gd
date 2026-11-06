extends Node3D
## The rail_aerial pieces alone under both renderers (RcRailAerial's colour-space proof): a column,
## a soffit, a pole, a lens, the wire ribbons and a street pool, at night (lamp_factor 1), lit only
## by a dim moon and a navy sky, from below as the refcam sees them. Prints each piece's mean
## display value so opengl3 and vulkan (lavapipe) can be compared, and saves OUT.
##
##   OUT=/tmp/a.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/rc5_rail_aerial/fwd_scene.tscn
## (VK_ICD_FILENAMES=.../lvp_icd.json for lavapipe; opengl3 for the Compatibility path.)

const K := FreewayKit.KIND_SCALE


func _ready() -> void:
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("road_wetness", 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.1)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.05
	add_child(sun)
	var base := FreewayKit.structure_material()
	var mat := RcRailAerial.structure_material(base)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The column face (kind 3), 0..8 m up, facing the camera (+z); UV2.y its height.
	_quad(st, Vector3(-3, 0, 0), Vector3(-1, 0, 0), Vector3(-1, 8, 0), Vector3(-3, 8, 0), Vector3.BACK, 3, 8.0)
	# The soffit (kind 4) facing down at 9 m.
	_quad(st, Vector3(-4, 9, -6), Vector3(4, 9, -6), Vector3(4, 9, 2), Vector3(-4, 9, 2), Vector3.DOWN, 4, 0.0)
	# A pole face (kind 6) and a lens (kind 7, flag 1.6) facing down.
	_quad(st, Vector3(1.5, 2, 0), Vector3(2.0, 2, 0), Vector3(2.0, 8, 0), Vector3(1.5, 8, 0), Vector3.BACK, 6, 6.0)
	_quad(st, Vector3(2.6, 3.0, -0.3), Vector3(3.2, 3.0, -0.3), Vector3(3.2, 3.0, 0.3), Vector3(2.6, 3.0, 0.3), Vector3.DOWN, 7, 0.0, RcRailAerial.LAMP_FLAG)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var y := 6.5 + 0.35 * k
		RcRailAerial.wire(ws, Vector3(-6, y, -2), Vector3(6, y, -2), 0.0065, RcRailAerial.KIND_WIRE, 1.0 + k * 2.0, 1.0 + k * 2.0)
	var wm := MeshInstance3D.new()
	wm.mesh = ws.commit()
	wm.material_override = RcRailAerial.wire_material()
	add_child(wm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.7, 14)
	cam.rotation_degrees = Vector3(18, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("OUT")
	if out != "":
		img.save_png(out)
	for r: Array in [["column", cam.unproject_position(Vector3(-2, 6.5, 0))], ["column_foot", cam.unproject_position(Vector3(-2, 1.0, 0))],
			["soffit", cam.unproject_position(Vector3(0, 9, -2))], ["pole", cam.unproject_position(Vector3(1.75, 6, 0))],
			["lens", cam.unproject_position(Vector3(2.9, 3.0, 0))]]:
		var p: Vector2 = (r[1] as Vector2) * Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		var c := img.get_pixelv(Vector2i(clampi(int(p.x), 0, img.get_width() - 1), clampi(int(p.y), 0, img.get_height() - 1)))
		print("FWDSCENE %s %d %d %d" % [r[0], roundi(c.r8), roundi(c.g8), roundi(c.b8)])
	# The brightest pixel on the wire rows (the lit one, nearest its pole).
	var best := 0
	var py := int(cam.unproject_position(Vector3(0, 6.5, -2)).y * img.get_height() / get_viewport().get_visible_rect().size.y)
	for x in img.get_width():
		for dy in range(-2, 3):
			best = maxi(best, img.get_pixel(x, clampi(py + dy, 0, img.get_height() - 1)).r8)
	print("FWDSCENE wire_peak %d" % best)
	get_tree().quit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, kind: int, hgt: float, flag := 0.0) -> void:
	var col := Color(0.72, 0.71, 0.68, float(kind) / K)
	if kind == 7:
		col = Color(RcRailAerial.LAMP_COLOR.r, RcRailAerial.LAMP_COLOR.g, RcRailAerial.LAMP_COLOR.b, float(kind) / K)
	elif kind == 6:
		col = Color(LightRailKit.POLE.r, LightRailKit.POLE.g, LightRailKit.POLE.b, float(kind) / K)
	var uvs := [Vector2(0, a.y), Vector2(1, b.y), Vector2(1, c.y), Vector2(0, d.y)]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(flag, hgt))
		st.add_vertex([a, b, c, d][i])
