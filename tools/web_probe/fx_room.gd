extends Node3D
## Particle effects side by side on a plain ground under the city's own Environment, small enough
## to load in a browser in a minute (web-build-5: the fire, smoke and hose blew out into huge
## green / white glare on the web only). Export it as the main scene
## (MAIN=res://tools/web_probe/fx_room.tscn tools/web_probe/export_probe.sh with AUTOPROBE=0)
## or run it natively:
##   OUT=/tmp/fx.png xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/web_probe/fx_room.tscn
## Left to right: FireSmoke (CarDamage's: HDR ramp x a dark colour), a fire puff (the plain puff on
## the web), HoseSpray (the smoke material, white ramp), HoseWater (hose_water.gdshader), a
## FountainPlume-like spray (lit). Prints FX <name> r g b: the mean over each column. Knobs:
## frames (40), fixed (1: fixed 30 fps particles), quit (1).

var _q := {}
var _cols: Array = []


func _arg(k: String, d: String) -> String:
	if _q.has(k):
		return _q[k]
	var v := OS.get_environment(k.to_upper())
	return v if v != "" else d


func _ready() -> void:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&", false):
				var kv := part.split("=")
				_q[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var we := city.get_node("WorldEnvironment").duplicate() as WorldEnvironment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	city.free()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.3)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.5, 14)
	cam.look_at(Vector3(0, 2.0, 0))
	cam.current = true
	var fixed := int(_arg("fixed", "0"))
	# FireSmoke as CarDamage builds it.
	_emit("smoke", -6.0, WeaponFX.smoke_material(), Color(0.035, 0.032, 0.03),
		WeaponFX._ramp([Color(8.0, 3.4, 1.1, 0.6), Color(1.6, 1.15, 1.0, 0.97), Color(1, 1, 1, 0.92),
			Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.0)]), 5.5, 32, Vector3(0, 1.5, 0), fixed)
	_emit("fire", -3.0, CarDamage.fire_material(), Color(1, 1, 1),
		WeaponFX._ramp([Color(1.25, 0.64, 0.07, 0.0), Color(1.3, 0.66, 0.07, 0.95), Color(1.05, 0.48, 0.05, 0.9),
			Color(0.65, 0.25, 0.03, 0.6), Color(0.3, 0.09, 0.015, 0.22), Color(0.06, 0.04, 0.025, 0.0)]), 0.85, 20, Vector3(0, 2.0, 0), fixed)
	_emit("spray", 0.0, WeaponFX.smoke_material(), Color(0.85, 0.87, 0.9),
		WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)]), 1.6, 12, Vector3(0, 0.4, 0), fixed)
	var hw := _emit("hose", 3.0, EmergencyCrew.water_material(), Color(1, 1, 1),
		WeaponFX._ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)]), 0.85, 60, Vector3(0, -9.8, 0), fixed)
	hw.particle_flag_align_y = true
	hw.direction = Vector3(0, 0.3, -1)
	hw.initial_velocity_min = 8.0
	hw.initial_velocity_max = 9.0
	var plain := StandardMaterial3D.new()
	plain.albedo_texture = WeaponFX.puff_texture()
	plain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plain.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	plain.billboard_keep_scale = true
	plain.vertex_color_use_as_albedo = true
	_emit("lit", 6.0, plain, Color(1, 1, 1), WeaponFX._ramp([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)]), 3.6, 60, Vector3(0, 0.5, 0), fixed)
	_shoot.call_deferred()


func _emit(n: String, x: float, mat: Material, col: Color, ramp: Gradient, life: float, amount: int, grav: Vector3, fixed: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = grav
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.4
	p.color = col
	p.color_ramp = ramp
	p.preprocess = 3.0
	if fixed > 0:
		p.fixed_fps = 30
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	p.mesh = q
	p.position = Vector3(x, 0.5, 0)
	add_child(p)
	_cols.append([n, x])
	return p


func _process(_delta: float) -> void:
	# slow=<ms>: every frame takes that long, as a city frame does in a browser under SwiftShader.
	var slow := int(_arg("slow", "0"))
	if slow > 0:
		OS.delay_msec(slow)


func _shoot() -> void:
	for i in int(_arg("frames", "40")):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var cam := get_viewport().get_camera_3d()
	for c in _cols:
		var a := cam.unproject_position(Vector3(c[1] - 1.2, 4.5, 0))
		var b := cam.unproject_position(Vector3(c[1] + 1.2, 0.3, 0))
		var s := Vector3.ZERO
		var k := 0
		for y in range(int(a.y), int(b.y), 2):
			for x in range(int(a.x), int(b.x), 2):
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					var cc := img.get_pixel(x, y)
					s += Vector3(cc.r, cc.g, cc.b)
					k += 1
		s = s / maxf(1.0, k) * 255.0
		print("FX %s %d %d %d" % [c[0], s.x, s.y, s.z])
	if OS.has_feature("web"):
		var half := img.duplicate() as Image
		print("PROBE_IMG fx %s" % Marshalls.raw_to_base64(half.save_png_to_buffer()))
	else:
		img.save_png(_arg("out", "/tmp/fx_room.png"))
	print("FX_DONE")
	if _arg("quit", "1") == "1" and not OS.has_feature("web"):
		get_tree().quit()
