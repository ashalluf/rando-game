extends Node3D
## The sea life kit alone (SeaLifeMesh, sea_life.gdshader, sea_spray.gdshader), in seconds: a
## buoy with its sea lions, dolphins mid-leap, a pelican gliding, one folded, a whale's back and
## splashes and a blow, on a flat blue plane under a sun. opengl3 under Xvfb:
##   OUT=kit.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . tools/sea_life/kit_shot.tscn --resolution 1280x720
## VIEW=buoy|dolphin|pelican|whale|all frames one group; NIGHT=1 lights the lantern; AGE=s the
## spray's age; LIFT/BARK/FOLD/FLAP set the poses.

var _frames := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.72)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var night := OS.get_environment("NIGHT") == "1"
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	if night:
		sun.light_energy = 0.08
		e.ambient_light_energy = 0.08
		e.background_color = Color(0.02, 0.03, 0.06)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.16, 0.22)
	sm.roughness = 0.15
	sea.material_override = sm
	add_child(sea)
	var age := float(OS.get_environment("AGE")) if OS.get_environment("AGE") != "" else 0.5
	var lift := float(OS.get_environment("LIFT")) if OS.get_environment("LIFT") != "" else -1.0
	# The buoy at the origin with four sea lions.
	var buoy := Transform3D(Basis(), Vector3(0, 0, 0))
	_one("buoy", buoy, Vector4(0, 0, 0, 0), Color(1, 1, 1))
	for j in 3:
		var ang := TAU * float(j) / 3.0
		var spot := Vector3(sin(ang) * SeaLife.LION_RING, SeaLifeMesh.BUOY_DECK_Y, cos(ang) * SeaLife.LION_RING)
		var b := Basis(Vector3.UP, ang + PI * 0.5)
		var l: float = [0.0, 1.0, 0.45, 0.8][j] if lift < 0.0 else lift
		var bark: float = float(OS.get_environment("BARK")) if OS.get_environment("BARK") != "" else (1.0 if j == 1 else 0.0)
		_one("sea_lion", buoy * Transform3D(b, spot), Vector4(l, [0.0, 0.4, -0.6, 0.2][j], bark, 0.3), SeaLife.lion_tint([0.9, 0.1, 0.5][j]))
	# Dolphins mid-leap and a roll, 12 m off.
	for j in 3:
		var pos := Vector3(-14.0 + float(j) * 3.5, float([1.2, 0.4, -0.05][j]), -6.0 - float(j) * 1.5)
		_one("dolphin", Transform3D(Basis.from_euler(Vector3([0.35, -0.5, 0.1][j], 1.4, 0.0), EULER_ORDER_YXZ), pos), Vector4(0.3 * float(j), 0.2, 0, 0), Color(1, 1, 1))
		if j == 0:
			_spray(Vector3(pos.x + 1.5, 0.0, pos.z), age, 0.0, 1.0)
	# Pelicans: one gliding, one flapping, one folded in a plunge, one sitting.
	var flap := float(OS.get_environment("FLAP")) if OS.get_environment("FLAP") != "" else 0.0
	_one("pelican", Transform3D(Basis.from_euler(Vector3(0.05, 2.3, 0.05), EULER_ORDER_YXZ), Vector3(8, 3.2, -6)), Vector4(0.0, flap, 0.0, 0), Color(1, 1, 1))
	_one("pelican", Transform3D(Basis.from_euler(Vector3(0.05, 2.3, 0.0), EULER_ORDER_YXZ), Vector3(11, 3.8, -9)), Vector4(0.25, 1.0, 0.0, 0), Color(1, 1, 1))
	_one("pelican", Transform3D(Basis.from_euler(Vector3(-1.1, 2.0, -0.6), EULER_ORDER_YXZ), Vector3(5, 4.5, -11)), Vector4(0.0, 0.0, 1.0, 0), Color(1, 1, 1))
	_one("pelican", Transform3D(Basis.from_euler(Vector3(0.0, 0.8, 0.0), EULER_ORDER_YXZ), Vector3(4, 0.02, -2)), Vector4(0.0, 0.0, 1.0, 0), Color(1, 1, 1))
	_spray(Vector3(5, 0.0, -14), age, 1.0, 1.0)
	# The whale's back and its blow, further out.
	_one("whale", Transform3D(Basis.from_euler(Vector3(0.05, 1.2, 0.0), EULER_ORDER_YXZ), Vector3(-30, -0.9, -60)), Vector4(0, 0.4, float(OS.get_environment("FLUKES")) if OS.get_environment("FLUKES") != "" else 0.0, 0), Color(1, 1, 1))
	_spray(Vector3(-34, 0.2, -61), age + 0.6, 2.0, 1.0)
	var cam := Camera3D.new()
	add_child(cam)
	var view := OS.get_environment("VIEW")
	match view:
		"buoy":
			cam.look_at_from_position(Vector3(4.5, 2.6, 6.0), Vector3(0, 1.0, 0))
			cam.fov = 45.0
		"dolphin":
			cam.look_at_from_position(Vector3(-8, 1.6, 6), Vector3(-11, 0.6, -6.5))
			cam.fov = 40.0
		"pelican":
			cam.look_at_from_position(Vector3(10, 4.0, 2.0), Vector3(7.5, 3.0, -8))
			cam.fov = 45.0
		"lion":
			cam.look_at_from_position(Vector3(2.6, 1.7, 2.4), Vector3(0.3, 0.85, 0.6))
			cam.fov = 40.0
		"whale":
			cam.look_at_from_position(Vector3(-10, 3.0, -20), Vector3(-31, 0.5, -60))
			cam.fov = 40.0
		_:
			cam.look_at_from_position(Vector3(6, 5, 16), Vector3(-6, 1.0, -12))
			cam.fov = 60.0
	cam.current = true


func _one(kind: String, xf: Transform3D, custom: Vector4, tint: Color) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = SeaLifeMesh.mesh(kind, 1 if OS.get_environment("LOD") == "1" else 0)
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, tint)
	mm.set_instance_custom_data(0, Color(custom.x, custom.y, custom.z, custom.w))
	mmi.multimesh = mm
	mmi.material_override = SeaLife.material(kind)
	mmi.custom_aabb = AABB(xf.origin - Vector3(10, 10, 10), Vector3(20, 20, 20))
	add_child(mmi)


func _spray(at: Vector3, age: float, kind: float, size: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = SeaLifeMesh.mesh("spray", 0)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(), at))
	mm.set_instance_custom_data(0, Color(age, kind, size, 1.5))
	mmi.multimesh = mm
	mmi.material_override = SeaLife.spray_material()
	if OS.get_environment("SPRAY_DEBUG") == "1":
		SeaLife.spray_material().set_shader_parameter("debug", 1)
	mmi.custom_aabb = AABB(at - Vector3(12, 2, 12), Vector3(24, 16, 24))
	add_child(mmi)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 6:
		var img := get_viewport().get_texture().get_image()
		var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "kit.png"
		img.save_png(out)
		print("saved ", out)
		get_tree().quit()
