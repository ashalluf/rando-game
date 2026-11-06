extends SceneTree
## Forward+ review i (docs/HANDOFF.md "Forward+ review i"): wave 8's small additive night pieces
## alone under a night sky, on EITHER renderer in a minute - so the Mac's renderer (Forward+ under
## lavapipe) can be held against the opengl3 still the piece was tuned on.
##
##   OUT=/tmp/b.png SCENE=runway VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/fwd_review_i/night_bits.gd --resolution 960x540
##
## SCENE=runway: a runway's edge lights' glow pools (JetTakeoff.infield()'s numbers: light_pool,
## radius 8, white 0.55 / blue 0.35, falloff 3) every 60 m down both edges and a landing light's beam
## (jet_beam.gdshader, JetTakeoff.BEAM_*) 4 m up, seen from the infield 1.1 m up.
## CAM / LOOK x,y,z (default the infield eye -60,1.1,-50 toward 40,1.5,30).
## SCENE=fire: the brush fire's glow card (fire_glow.gdshader, BrushFireLook) 3 km off over a
## dark ridge; LEVEL its level (1 night).
## FIX=0 the materials as on main before this review (the A/B: display_add_fwd off, the beam's
## handover off). FRAMES (default 24). Names no game class (compiled before the autoloads).

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _initialize() -> void:
	_run.call_deferred()


func _pool(tint: Color, strength: float, falloff: float, fix: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_pool.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("falloff", falloff)
	mat.set_shader_parameter("display_add_fwd", fix)
	return mat


func _run() -> void:
	var fix := _env("FIX", "1") != "0"
	RenderingServer.global_shader_parameter_set("fwd_review_i", 1.0 if fix else 0.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	RenderingServer.global_shader_parameter_set("origin_shift", Vector3.ZERO)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.15, 0.24)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.6, 0.7, 1.0)
	root3.add_child(moon)
	var scene := _env("SCENE", "runway")
	if scene == "runway":
		_runway(root3, fix)
	elif scene == "fire":
		_fire(root3)
	for i in int(_env("FRAMES", "24")):
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(_env("OUT", "/tmp/night_bits.png"))
	print("saved ", _env("OUT", "/tmp/night_bits.png"))
	quit()


func _runway(root3: Node3D, fix: bool) -> void:
	# Grass (the infield) either side of a 45 m asphalt strip along x at z 30.
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 400)
	grass.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.25, 0.16)
	grass.material_override = gm
	root3.add_child(grass)
	var asph := MeshInstance3D.new()
	var am := PlaneMesh.new()
	am.size = Vector2(1200, 45)
	asph.mesh = am
	var asm := StandardMaterial3D.new()
	asm.albedo_color = Color(0.12, 0.12, 0.12)
	asph.material_override = asm
	asph.position = Vector3(0, 0.02, 30.0)
	root3.add_child(asph)
	var white := QuadMesh.new()
	white.size = Vector2.ONE
	white.material = _pool(Color(1.0, 0.9, 0.72), 0.55, 3.0, fix)
	var blue := QuadMesh.new()
	blue.size = Vector2.ONE
	blue.material = _pool(Color(0.35, 0.5, 1.0), 0.35, 3.0, fix)
	var flat := Basis(Vector3.RIGHT, -PI * 0.5).scaled_local(Vector3(16.0, 16.0, 1.0))
	for side in [7.5, 52.5]:
		for i in 20:
			var mi := MeshInstance3D.new()
			mi.mesh = white
			mi.transform = Transform3D(flat, Vector3(-500.0 + i * 60.0, 0.05, side))
			root3.add_child(mi)
	# A taxiway's blue edge lights nearer the eye.
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = blue
		mi.transform = Transform3D(flat, Vector3(-200.0 + i * 30.0, 0.05, -22.0))
		root3.add_child(mi)
	# A landing light's beam: JetTakeoff.build_beams()'s cone (55 m, half angle 0.09, strength
	# 0.07), from a lamp 4 m up pointing along +x and 8 degrees down, 80 m from the eye.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 55.0 * tan(0.09)
	cyl.height = 55.0
	cyl.radial_segments = 14
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/jet_beam.gdshader")
	bm.set_shader_parameter("strength", 0.07)
	cyl.material = bm
	var dir := Vector3(1.0, -tan(deg_to_rad(8.0)), 0.0).normalized()
	var y := -dir
	var x := y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	var beam := MeshInstance3D.new()
	beam.mesh = cyl
	beam.transform = Transform3D(Basis(x, y, z), Vector3(-40.0, 4.0, 30.0) + dir * 27.5)
	root3.add_child(beam)
	var cam := Camera3D.new()
	cam.fov = 55.0
	root3.add_child(cam)
	cam.look_at_from_position(_v3(_env("CAM", "-60,1.1,-50")), _v3(_env("LOOK", "40,1.5,30")), Vector3.UP)
	cam.current = true


## The Santa Ana brush fire's line on the crest (SantaAnaFx's glow card, BrushFireLook's look:
## 640 x 300 m, the site 70 m above its foot) 3 km off behind a dark ridge, level 1 (night).
func _fire(root3: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fire_glow.gdshader")
	m.set_shader_parameter("look", 1.0)
	m.set_shader_parameter("flank_fall", 0.42)
	m.set_shader_parameter("foot", (70.0 - 40.0) / 300.0)
	m.set_shader_parameter("level", float(_env("LEVEL", "1.0")))
	var card := MeshInstance3D.new()
	card.mesh = quad
	card.material_override = m
	card.transform = Transform3D(Basis.from_scale(Vector3(640.0, 300.0, 1.0)), Vector3(0.0, 330.0, -3000.0))
	root3.add_child(card)
	var ridge := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6000.0, 400.0, 40.0)
	ridge.mesh = bm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.05, 0.045, 0.04)
	ridge.material_override = rm
	ridge.position = Vector3(0.0, 145.0, -2900.0)
	root3.add_child(ridge)
	var cam := Camera3D.new()
	cam.fov = 22.0
	cam.far = 8000.0
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 20.0, 0.0), Vector3(0.0, 400.0, -3000.0), Vector3.UP)
	cam.current = true
