extends Node3D
## web-hero-blue: the MultiMesh update pattern alone in a small room, for the browser. Two rows of
## flat quads that must stay in two neat rows: the LEFT MultiMesh written with set_instance_*()
## every frame while its visible_instance_count changes (ContactShadows', WetCarGlints' pattern),
## the RIGHT one written whole (multimesh.buffer). Prints MM_ROOM lines with the frame's pixels
## outside the rows (stray triangles) for each side. Query: mode=inst|buffer|both (both).

var _a: MultiMesh
var _b: MultiMesh
var _f := 0
const N := 80
var _slow := 0
var _ma: MultiMeshInstance3D


func _mm(x0: float, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := PlaneMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = N
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.position = Vector3(x0, 0, 0)
	mi.custom_aabb = AABB(Vector3(-20, -5, -40), Vector3(40, 10, 60))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_ma = mi
	return mm


func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9, 8)
	cam.rotation_degrees = Vector3(-50, 0, 0)
	add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var mat := load("res://shaders/contact_shadow.gdshader")
	var m := ShaderMaterial.new()
	m.shader = mat
	m.render_priority = -2
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String and (search as String).contains("slow="):
			_slow = int((search as String).split("slow=")[1].split("&")[0])
	_a = _mm(-4.0, m)
	_b = _mm(4.0, m)


func _xf(i: int, t: float) -> Transform3D:
	var b := Basis(Vector3(1.6, 0, 0), Vector3.UP, Vector3(0, 0, 2.6)).rotated(Vector3.UP, 0.3 * sin(t + i))
	return Transform3D(b, Vector3(0.0, 0.02, -float(i) * 1.2 + 0.5 * sin(t * 0.7 + i)))


func _process(_d: float) -> void:
	_f += 1
	var t := _f * 0.37
	if _slow > 0:
		OS.delay_msec(_slow)
	var n := 6 + (_f * 7) % 12
	_ma.custom_aabb = AABB(Vector3(-30 - _f % 3, -10, -60), Vector3(60, 20, 90))
	for i in n:
		_a.set_instance_transform(i, _xf(i, t))
		_a.set_instance_custom_data(i, Color(2.2, 1.2, 0.0, 0.0))
		_a.set_instance_color(i, Color(0.4, 0.22, 0.0, 0.9))
	_a.visible_instance_count = n
	var buf := PackedFloat32Array()
	buf.resize(N * 20)
	for i in n:
		var x := _xf(i, t)
		var o := i * 20
		buf[o] = x.basis.x.x; buf[o + 1] = x.basis.y.x; buf[o + 2] = x.basis.z.x; buf[o + 3] = x.origin.x
		buf[o + 4] = x.basis.x.y; buf[o + 5] = x.basis.y.y; buf[o + 6] = x.basis.z.y; buf[o + 7] = x.origin.y
		buf[o + 8] = x.basis.x.z; buf[o + 9] = x.basis.y.z; buf[o + 10] = x.basis.z.z; buf[o + 11] = x.origin.z
		buf[o + 12] = 0.4; buf[o + 13] = 0.22; buf[o + 14] = 0.0; buf[o + 15] = 0.9
		buf[o + 16] = 2.2; buf[o + 17] = 1.2; buf[o + 18] = 0.0; buf[o + 19] = 0.0
	_b.buffer = buf
	_b.visible_instance_count = n
	if _f % 4 == 0 and _f > 4:
		_report()


func _report() -> void:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	# Dark pixels in each half: the rows' share is fixed; strays add to it and change frame to frame.
	var dark := [0, 0]
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).get_luminance() < 0.45:
				dark[0 if x < w / 2 else 1] += 1
	print("MM_ROOM f=%d inst_dark=%d buffer_dark=%d" % [_f, dark[0], dark[1]])
	if _f % 40 == 0:
		img.resize(w / 2, h / 2)
		print("PROBE_IMG mm%d %s" % [_f, Marshalls.raw_to_base64(img.save_png_to_buffer())])
