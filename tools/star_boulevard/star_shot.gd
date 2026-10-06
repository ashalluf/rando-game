extends SceneTree
## A few metres of the walk of fame and a forecourt slab alone under a sun, for the shader loop
## (seconds, no city):
##   OUT=/tmp/s.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/star_boulevard/star_shot.gd
## CAM=x,y,z LOOK=x,y,z (default looking down at the first star), MODE=walk|forecourt.
func _initialize() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/walk_of_fame.gdshader")
	mat.set_shader_parameter("atlas", load("res://assets/textures/star_boulevard/walk_atlas.png"))
	mat.set_shader_parameter("name_count", 120)
	var forecourt := OS.get_environment("MODE") == "forecourt"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 6.0
	var d := 1.4 if not forecourt else 5.0
	var pts := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(pts[i].x, pts[i].z))
		st.set_uv2(Vector2(1.0, 1.0 if forecourt else 0.0))
		st.add_vertex(pts[i])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	root.add_child(env)
	var cam := Camera3D.new()
	root.add_child(cam)
	var c := Vector3(0.5, 1.2, 1.5)
	var l := Vector3(0.5, 0.0, 0.7)
	if forecourt:
		c = Vector3(1.9, 1.8, -0.2)
		l = Vector3(1.9, 0.0, 1.9)
	if OS.get_environment("CAM") != "":
		var a := OS.get_environment("CAM").split(",")
		c = Vector3(float(a[0]), float(a[1]), float(a[2]))
	if OS.get_environment("LOOK") != "":
		var a := OS.get_environment("LOOK").split(",")
		l = Vector3(float(a[0]), float(a[1]), float(a[2]))
	cam.look_at_from_position(c, l)
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/star.png")
	quit()
