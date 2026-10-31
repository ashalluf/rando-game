extends Node
## Trees under light (tree-light-2): a pavement and a lawn planted with the city's trees through
## the REAL path - MultiMeshBatch, so every tree casts from its shadow twin and draws its LOD
## ladder exactly as a chunk does - lit by the city scene's own WorldEnvironment, Sun and DayNight
## held at an hour. Seconds a still on opengl3; a few minutes on lavapipe Forward+ (the scene is
## small enough). Judge crowns' self-shadowing, translucency, the canopy shadow on the ground and
## the leaf edges at 5-20 m.
##
##   OUT=build/tl/noon xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . res://tools/tree_light/tree_light_shot.tscn --resolution 1280x720 -- --hour=13
##   Forward+: VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ... --rendering-driver vulkan
##
## Env: OUT (prefix: <OUT>_<view>.png), VIEWS=name,... (default all of VIEW_DEFS), FRAMES (default
## 10; 24 on Forward+ for TAA and the exposure), TAA=1, WIND=n, HOLD=1 holds shader TIME (the
## pair of an A/B is the same frame), AB=name saves every view again with TreeLight off
## (<view>_off.png). CAM=x,y,z LOOK=x,y,z FOV=n for one free view named "free".
## The row runs along +X at z 0 (pavement z -3..3), the lawn grove at z -14..-30.

const VIEW_DEFS := {
	"street": [Vector3(-3.0, 1.7, 9.0), Vector3(4.0, 3.2, 0.0), 62.0],
	"crown5": [Vector3(-3.5, 1.7, 5.0), Vector3(-3.0, 5.5, 0.0), 60.0],
	"edge10": [Vector3(2.0, 1.7, 10.0), Vector3(3.0, 6.0, 0.0), 50.0],
	"edge20": [Vector3(-6.0, 1.7, 20.0), Vector3(-4.0, 5.0, 0.0), 40.0],
	"palm": [Vector3(13.0, 1.6, 7.0), Vector3(16.0, 8.0, 0.0), 60.0],
	"ground": [Vector3(-2.0, 9.0, 12.0), Vector3(-2.0, 0.0, -6.0), 60.0],
	"grove": [Vector3(0.0, 1.7, -4.0), Vector3(0.0, 3.0, -22.0), 62.0],
	"back": [Vector3(4.0, 1.6, -8.0), Vector3(2.0, 5.0, 2.0), 62.0],
}

# [kind, arg, x, z, scale]: "scan" PropFactory.model_tree(arg), "palm" palm(arg), "la" LaTrees.
const ROW := [
	["scan", 4, -18.0, 0.0, 0.42], ["scan", 0, -9.0, 0.0, 1.45], ["scan", 2, -3.0, 0.0, 1.5],
	["scan", 1, 3.0, 0.0, 1.6], ["palm", 0, 10.0, 0.0, 1.0], ["palm", 1, 16.0, 0.0, 1.0],
	["la", 3, 24.0, 0.0, 0.75], ["la", 2, 31.0, 0.0, 1.0],
	["scan", 0, -10.0, -18.0, 1.3], ["scan", 1, -2.0, -22.0, 1.5], ["scan", 2, 7.0, -17.0, 1.4],
	["scan", 0, 14.0, -24.0, 1.2], ["scan", 3, -16.0, -26.0, 1.0], ["palm", 2, 2.0, -30.0, 1.1],
]

var _ground_mat: ShaderMaterial


func set_ground_haze(_color: Color, _sun_direction: Vector3) -> void:
	pass


func set_ground_smog(_amount: float, _color: Color) -> void:
	pass


func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for keep in ["WorldEnvironment", "Sun", "DayNight"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = city.get("sun_rotation_degrees")
	var dn: Node = get_node_or_null("DayNight")
	if dn:
		dn.call("set_paused", true)
	city.free()
	if OS.get_environment("TAA") == "1":
		get_viewport().use_taa = true
	var wind := float(OS.get_environment("WIND")) if OS.get_environment("WIND") != "" else 1.0
	RenderingServer.global_shader_parameter_set("wind_factor", wind)
	var stage := Node3D.new()
	add_child(stage)
	_box(stage, Vector3(140.0, 0.15, 6.0), Vector3(10.0, 0.075, 0.0), _mat(Color(0.52, 0.5, 0.47), 0.9))
	_box(stage, Vector3(140.0, 0.02, 20.0), Vector3(10.0, -0.01, 13.0), _mat(Color(0.12, 0.12, 0.125), 0.85))
	_box(stage, Vector3(140.0, 0.1, 30.0), Vector3(10.0, 0.05, -18.0), _mat(Color(0.2, 0.3, 0.1), 0.95))
	var batch := MultiMeshBatch.new()
	var i := 0
	for r: Array in ROW:
		var m: Mesh
		match String(r[0]):
			"scan":
				m = PropFactory.model_tree(int(r[1]))
			"palm":
				m = PropFactory.palm(int(r[1]))
			_:
				m = LaTrees.mesh(int(r[1]), 0)
		var s: float = r[4]
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)).rotated(Vector3.UP, float(r[2]) * 0.37 + float(r[3])), Vector3(float(r[2]), 0.15, float(r[3])))
		# Each tree its own batch (the scale decides a ladder batch's LOD bias).
		batch.add("t%d_%s_%d" % [i, r[0], r[1]], m, xf, Color.WHITE, Color(0.2, 0.5, 0.5, 0.8))
		i += 1
	batch.build(stage)
	await get_tree().process_frame
	if sun:
		print("SUN dir ", sun.global_basis.z, " energy ", sun.light_energy)
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	cam.attributes = attrs
	if OS.get_environment("HOLD") == "1":
		for f in 3:
			await get_tree().process_frame
		Engine.time_scale = 0.0
	var views: Array = []
	if OS.get_environment("CAM") != "":
		views.append(["free", [_vec(OS.get_environment("CAM")), _vec(OS.get_environment("LOOK")), float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0]])
	elif OS.get_environment("VIEWS") != "":
		for v in OS.get_environment("VIEWS").split(","):
			views.append([v, VIEW_DEFS[v]])
	else:
		for v: String in VIEW_DEFS:
			views.append([v, VIEW_DEFS[v]])
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 10
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "tree_light"
	var ab := OS.get_environment("AB") == "1"
	for v: Array in views:
		var d: Array = v[1]
		cam.fov = d[2]
		cam.look_at_from_position(d[0], d[1], Vector3.UP)
		cam.make_current()
		for pass_i in (2 if ab else 1):
			if ab:
				TreeLight.set_all(pass_i == 0)
			for f in frames:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := "%s_%s%s.png" % [out, v[0], "_off" if pass_i == 1 else ""]
			img.save_png(path)
			print("SAVED ", path)
	if ab:
		TreeLight.set_all(true)
	get_tree().quit()


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(stage: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = mat
	stage.add_child(mi)


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
