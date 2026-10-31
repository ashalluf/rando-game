extends Node3D
## The power_wire shader alone: six 28 mm wires from 10 to 400 m, lit by a sun, against a flat sky
## (OUT=png). Seconds, opengl3 under Xvfb: res://tools/ridges/wire_test.tscn --resolution 640x360
func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.6, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	add_child(env)
	var w := RidgeSystem.Wires.new()
	for i in 6:
		var d: float = [10.0, 20.0, 40.0, 70.0, 150.0, 400.0][i]
		w.seg(Vector3(-d, (-1.5 + i * 0.6) * d / 10.0, -d), Vector3(d, (-1.5 + i * 0.6) * d / 10.0, -d), 0.0145, 1.0, Color(0.36, 0.37, 0.37), 0)
	var img := Image.create(4, 1, false, Image.FORMAT_R8)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/power_wire.gdshader")
	mat.set_shader_parameter("covered", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("covered_width", 4)
	mat.set_shader_parameter("viewport_px", get_viewport().get_visible_rect().size)
	var mi := MeshInstance3D.new()
	mi.mesh = w.mesh(mat)
	add_child(mi)
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "wire_test.png")
	get_tree().quit()
