extends Node3D
## The alley at noon alone (AlleyNoon, refcam `alley_noon`): a 40 m alley slab on the real alley
## material (the water on, as AlleyNight's chunk copy has it) between two tall walls, a noon sun
## from the south, and the props AlleyNoon rebuilds - a cart pair, a leaning mattress, a back door's
## stoop, a dumpster - written by AlleyKit into the alley's real upright material. Small enough for
## Forward+ under lavapipe (the city OOMs it), so it is the proof on the Mac's renderer:
##
##   OUT=/tmp/n.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/rc5_alley_noon/noon_shot.tscn \
##     --resolution 960x540
##
## (opengl3 for the Compatibility path.) ALLEY_NOON=0 is the A/B; HOUR= (default 12) sets the
## lamp_factor the water reads (0 by day; NIGHT=1 forces 1, the night's water).

const HW := 3.0
const LENGTH := 40.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("road_wetness", 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.55, 0.7, 0.9) if not night else Color(0.06, 0.07, 0.11))
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	# Due south (+z here is south), 56 degrees up: the alley runs along x, so the south wall's
	# foot is in shade and the north wall's top in sun.
	sun.rotation = Vector3(deg_to_rad(-56.0), 0.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 0.0 if night else 1.0
	add_child(sun)
	# The slab: the alley's own section, the water on.
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
				g.set_uv2(Vector2(HW, 0.7))
				g.set_normal(Vector3.UP)
				g.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit()
	var mat := Alleys.ground_material().duplicate() as ShaderMaterial
	var heads: Array[Vector4] = []
	for i in AlleyNight.MAX_HEADS:
		heads.append(Vector4(0.0, -1000.0, 0.0, 0.0))
	mat.set_shader_parameter("wet_on", 1.0)
	mat.set_shader_parameter("lamp_heads", heads)
	mat.set_shader_parameter("lamp_count", 0)
	mi.material_override = mat
	add_child(mi)
	for side: float in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(LENGTH, 20.0, 0.4)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.35, 0.16, 0.1) if side < 0.0 else Color(0.36, 0.35, 0.33)
		bm.material = wm
		wall.mesh = bm
		wall.position = Vector3(LENGTH * 0.5, 10.0, side * (HW + 0.45))
		add_child(wall)
	# The props, through AlleyKit into the alley's upright material (x along the wall, z out).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_xf := func(s: float, side: float) -> Transform3D:
		# Local +z out of the wall into the alley.
		var zdir := Vector3(0.0, 0.0, -side)
		var xdir := Vector3.UP.cross(zdir)
		return Transform3D(Basis(xdir, Vector3.UP, zdir), Vector3(s, 0.0, side * HW))
	IndustrialKit.place(st, wall_xf.call(6.0, -1.0), Color.WHITE, AlleyKit.cart.bind(st, AlleyKit.CART_PAINT[2], Color(0.06, 0.06, 0.07)))
	IndustrialKit.place(st, wall_xf.call(6.75, -1.0), Color.WHITE, AlleyKit.cart.bind(st, AlleyKit.CART_PAINT[1], Color(0.06, 0.06, 0.07)))
	IndustrialKit.place(st, wall_xf.call(10.0, 1.0), Color.WHITE, AlleyKit.mattress.bind(st, Color(0.78, 0.76, 0.7)))
	IndustrialKit.place(st, wall_xf.call(13.0, -1.0), Color.WHITE, AlleyKit.back_door.bind(st, AlleyKit.DOOR_PAINT[4], "", true))
	IndustrialKit.place(st, wall_xf.call(16.0, 1.0), Color.WHITE, AlleyKit.dumpster.bind(st, Color(0.13, 0.36, 0.18), Color(0.06, 0.06, 0.07), "BASIN HAULING", true))
	var props := MeshInstance3D.new()
	props.mesh = st.commit()
	props.material_override = IndustrialKit.walls_material()
	add_child(props)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.position = Vector3(-0.5, 1.7, 0.6)
	cam.look_at(Vector3(20.0, 0.9, 0.0))
	if OS.get_environment("CLOSE") == "1":
		cam.position = Vector3(6.5, 1.5, 0.4)
		cam.look_at(Vector3(10.0, 0.8, 2.6))
	for i in 24:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "build/alley_noon.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("NOON_SHOT saved ", out)
	get_tree().quit()
