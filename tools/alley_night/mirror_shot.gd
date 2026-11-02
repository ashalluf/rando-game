extends Node3D
## The alley's water at night alone (AlleyNight, alley_ground.gdshader's `wet_on`): a 40 m alley
## slab on the real alley material between two dark walls, three bulkhead lamp heads (a warm, a
## cool, a warm) with a real OmniLight each, AgX and a night sky. Small enough for Forward+ under
## lavapipe (the city's chunks OOM it), so it is the colour proof on the Mac's renderer:
##
##   OUT=/tmp/m.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/alley_night/mirror_shot.tscn \
##     --resolution 960x540
##
## (opengl3 for the Compatibility path.) WET=0 draws the dry slab (the shared material, no
## mirror); SEED= the run's seed (0..1: under 0.5 the asphalt alley, over it concrete).

const HW := 2.8
const LENGTH := 40.0
const LAMPS := [Vector3(6.0, 3.0, -2.7), Vector3(15.0, 3.0, 2.7), Vector3(26.0, 3.0, -2.7)]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root3 := self
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("road_wetness", 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.06, 0.07, 0.11))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var seed01 := float(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 0.7
	var g := SurfaceTool.new()
	g.begin(Mesh.PRIMITIVE_TRIANGLES)
	var os := [-HW, -0.45, 0.0, 0.45, HW]
	var n := 40
	for j in n:
		var sa := LENGTH * float(j) / float(n)
		var sb := LENGTH * float(j + 1) / float(n)
		for i in os.size() - 1:
			var oa: float = os[i]
			var ob: float = os[i + 1]
			var pts := [Vector3(sa, Alleys.surface(oa, HW), oa), Vector3(sb, Alleys.surface(oa, HW), oa), Vector3(sb, Alleys.surface(ob, HW), ob), Vector3(sa, Alleys.surface(ob, HW), ob)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = pts[k]
				g.set_color(Color(0.5 / 16.0, 0.0, 0.0, 1.0))
				g.set_uv(Vector2(p.x, p.z))
				g.set_uv2(Vector2(HW, seed01))
				g.set_normal(Vector3.UP)
				g.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit()
	var mat := Alleys.ground_material()
	if OS.get_environment("WET") != "0":
		mat = mat.duplicate() as ShaderMaterial
		var heads: Array[Vector4] = []
		for i in AlleyNight.MAX_HEADS:
			heads.append(Vector4(0.0, -1000.0, 0.0, 0.0))
		for i in LAMPS.size():
			var l: Vector3 = LAMPS[i]
			heads[i] = Vector4(l.x, l.y, l.z, 0.0 if i == 1 else 1.0)
		mat.set_shader_parameter("wet_on", 1.0)
		mat.set_shader_parameter("lamp_heads", heads)
		mat.set_shader_parameter("lamp_count", LAMPS.size())
	mi.material_override = mat
	root3.add_child(mi)
	for side: float in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(LENGTH, 10.0, 0.4)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.35, 0.16, 0.1) if side < 0.0 else Color(0.3, 0.3, 0.29)
		bm.material = wm
		wall.mesh = bm
		wall.position = Vector3(LENGTH * 0.5, 5.0, side * (HW + 0.45))
		root3.add_child(wall)
	for i in LAMPS.size():
		var l: Vector3 = LAMPS[i]
		var o := OmniLight3D.new()
		o.position = l + Vector3(0.0, -0.1, -signf(l.z) * 0.3)
		o.light_color = Color(0.82, 0.88, 1.0) if i == 1 else Color(1.0, 0.72, 0.42)
		o.light_energy = 2.0
		o.omni_range = 7.5
		root3.add_child(o)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		var bmat := StandardMaterial3D.new()
		bmat.emission_enabled = true
		bmat.emission = o.light_color
		bmat.emission_energy_multiplier = 6.0
		sm.material = bmat
		bulb.mesh = sm
		bulb.position = l
		root3.add_child(bulb)
	var cam := Camera3D.new()
	cam.fov = 55.0
	root3.add_child(cam)
	cam.position = Vector3(-1.0, 1.7, 0.6)
	cam.look_at(Vector3(20.0, 0.9, 0.0))
	for i in 20:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "build/alley_mirror.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("MIRROR_SHOT saved ", out)
	get_tree().quit()
