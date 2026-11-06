extends SceneTree
## The ballpark's fireworks alone (docs/HANDOFF.md "Fireworks over the ballpark from Stadium Way"):
## the show's star and smoke meshes on Fireworks' own materials, its flash light, a ground plane and
## a box standing in for the stadium, under city.tscn's Environment, seen from the refcam's
## distance - the look on EITHER renderer in a minute (Forward+ under lavapipe, which cannot hold the
## city). No city, no plan: the show seed is the ballpark's for night 0 on seed 1337.
##
##   OUT=build/fw.png T=31.2 LOOK5=1 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##     godot --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/rc5_fireworks/fw_shot.gd --resolution 960x540   (under xvfb-run)
##
## Env: OUT, T (show seconds, default 31.2), LOOK5 (1 the second look, 0 the old), DIST (metres from
## the site, default 470), FRAMES (default 40).

var _fw: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _env_f(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d


func _city_environment() -> Environment:
	var ps: PackedScene = load("res://scenes/levels/city.tscn")
	var st := ps.get_state()
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "environment":
				return st.get_node_property_value(i, p)
	return Environment.new()


func _run() -> void:
	_fw = load("res://scripts/world/fireworks.gd")
	var look := _env_f("LOOK5", 1.0)
	var t_now := _env_f("T", 31.2)
	var dist := _env_f("DIST", 470.0)
	var root := Node3D.new()
	get_root().add_child(root)
	var we := WorldEnvironment.new()
	# The city's tonemap, grade, glow and fog, but a night background (the sky shader's defaults are
	# noon without DayNight driving them).
	var env: Environment = _city_environment().duplicate()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.03, 0.035, 0.06)
	env.ambient_light_energy = 1.0
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	we.environment = env
	root.add_child(we)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.05, 0.06, 0.1))
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.09
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(moon)
	# Ground and a stadium stand-in (a ring of boxes 140 m across, floodlit warm).
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.22, 0.23)
	gm.roughness = 0.9
	ground.material_override = gm
	root.add_child(ground)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.75, 0.74, 0.72)
	for k in 16:
		var a := TAU * k / 16.0
		var b := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(30, 28, 10)
		b.mesh = bx
		b.material_override = bm
		b.position = Vector3(cos(a) * 75.0, 14.0, -170.0 + sin(a) * 75.0)
		b.rotation.y = -a + PI * 0.5
		root.add_child(b)
	var flood := OmniLight3D.new()
	flood.position = Vector3(0, 45, -170)
	flood.omni_range = 220.0
	flood.light_energy = 6.0
	flood.light_color = Color(1.0, 0.95, 0.85)
	root.add_child(flood)
	# The show: at the origin, line along +x.
	var seed: int = _fw.call("night_seed", 1337, 0, "stadium")
	var line := Vector2(1, 0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/fireworks.gdshader")
	var km := ShaderMaterial.new()
	km.shader = load("res://shaders/fireworks_smoke.gdshader")
	km.set_shader_parameter("puff_tex", load("res://scripts/weapons/weapon_fx.gd").call("puff_texture"))
	km.set_shader_parameter("puffs", 4.0)
	for m: ShaderMaterial in [sm, km]:
		m.set_shader_parameter("line_dir", line)
		m.set_shader_parameter("spread", 110.0)
		m.set_shader_parameter("h_min", 95.0)
		m.set_shader_parameter("h_max", 190.0)
		m.set_shader_parameter("now", t_now)
		m.set_shader_parameter("show_seed", seed)
		m.set_shader_parameter("strength", 1.0)
		m.set_shader_parameter("wind", Vector2(1.0, 0.36))
		m.set_shader_parameter("look5", look)
	if look > 0.5:
		km.set_shader_parameter("under_light", _fw.get("STADIUM_UNDER"))
	var stars := MeshInstance3D.new()
	stars.mesh = _fw.call("star_mesh")
	stars.material_override = sm
	stars.custom_aabb = AABB(Vector3(-900, -60, -900), Vector3(1800, 700, 1800))
	root.add_child(stars)
	var smoke := MeshInstance3D.new()
	smoke.mesh = _fw.call("smoke_mesh")
	smoke.material_override = km
	smoke.custom_aabb = AABB(Vector3(-1200, -60, -1200), Vector3(2400, 700, 2400))
	root.add_child(smoke)
	# The flash: Fireworks.advance_site()'s sum over the live breaks.
	var sum := Color(0, 0, 0)
	var at := Vector3.ZERO
	var wsum := 0.0
	for b in range(int(floor(t_now / 0.4)) - 24, int(floor(t_now / 0.4)) + 1):
		var sh: Dictionary = _fw.call("shell", seed, b, line, 110.0, 95.0, 190.0)
		if sh.is_empty():
			continue
		var a: float = t_now - float(sh.burst_t)
		if a < 0.0 or a > float(sh.life):
			continue
		var lvl: float = float(_fw.call("flash_level", a, float(sh.life), int(sh.type))) * float(sh.size)
		sum += (_fw.call("shell_color", sh) as Color) * lvl
		at += Vector3(sh.burst) * lvl
		wsum += lvl
	km.set_shader_parameter("flash", Vector3(sum.r, sum.g, sum.b))
	km.set_shader_parameter("flash_at", at / wsum if wsum > 0.0 else Vector3(0, 200, 0))
	if wsum > 0.0:
		var l := OmniLight3D.new()
		l.position = at / wsum
		l.omni_range = 1200.0
		l.omni_attenuation = float(_fw.get("LOOK5_ATTENUATION")) if look > 0.5 else 1.2
		var mx := maxf(sum.r, maxf(sum.g, sum.b))
		l.light_color = Color(sum.r / mx, sum.g / mx, sum.b / mx)
		l.light_energy = minf(wsum * 5.0, 30.0)
		root.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 12000.0
	root.add_child(cam)
	cam.position = Vector3(dist * 0.6, 22.0, dist * 0.8)
	cam.look_at(Vector3(0, 95.0, -60.0))
	cam.make_current()
	var px := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / float(get_root().get_visible_rect().size.y)
	sm.set_shader_parameter("px_angle", px)
	for i in int(_env_f("FRAMES", 40.0)):
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "build/fw.png"
	get_root().get_texture().get_image().save_png(out)
	print("FW_SHOT saved %s look5 %.0f t %.1f flash %.2f" % [out, look, t_now, wsum])
	quit()
