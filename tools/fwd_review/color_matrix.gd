## The colour-space matrix in seconds: one quad, a straight-down sun, a linear tonemapper, each way a
## colour reaches a spatial shader (source_color / plain uniform, source_color / plain texture,
## vertex colour, emission, a Color set from script), printing the pixel. Run it on both renderers:
##   xvfb-run -a godot --rendering-driver opengl3|vulkan --display-driver x11 --audio-driver Dummy \
##     --script tools/fwd_review/color_matrix.gd --resolution 320x240
## 4.7.2 (fwd-review-e): Compatibility prints 0.80 0.70 0.55 for every case (all raw); Forward+
## the same for source_color uniforms and textures and a Color set from script (decoded), and
## 0.91 0.86 0.78 for plain uniforms, plain textures, vertex colours and constants (raw, read as
## linear: brighter). CLAUDE.md's colour-space trap, measured.
extends SceneTree
const CASES := {
	"src_uniform": "uniform vec3 c : source_color = vec3(0.8, 0.7, 0.55); void fragment() { ALBEDO = c; }",
	"plain_uniform": "uniform vec3 c = vec3(0.8, 0.7, 0.55); void fragment() { ALBEDO = c; }",
	"src_tex": "uniform sampler2D t : source_color; void fragment() { ALBEDO = texture(t, UV).rgb; }",
	"plain_tex": "uniform sampler2D t; void fragment() { ALBEDO = texture(t, UV).rgb; }",
	"vcolor": "void fragment() { ALBEDO = COLOR.rgb; }",
	"emit_src": "uniform vec3 c : source_color = vec3(0.8, 0.7, 0.55); void fragment() { ALBEDO = vec3(0.0); EMISSION = c; }",
	"emit_const": "void fragment() { ALBEDO = vec3(0.0); EMISSION = vec3(0.8, 0.7, 0.55); }",
	"emit_set_color": "uniform vec3 c = vec3(0.0); void fragment() { ALBEDO = vec3(0.0); EMISSION = c; }",
}
func _initialize():
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.BLACK
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	root.add_child(env)
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8); img.fill(Color(0.8, 0.7, 0.55))
	var tex := ImageTexture.create_from_image(img)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-1,0,-1), Vector3(1,0,-1), Vector3(1,0,1), Vector3(-1,0,-1), Vector3(1,0,1), Vector3(-1,0,1)]:
		st.set_color(Color(0.8, 0.7, 0.55)); st.set_normal(Vector3.UP); st.set_uv(Vector2(p.x, p.z) * 0.5 + Vector2(0.5, 0.5)); st.add_vertex(p * 10.0)
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); root.add_child(mi)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-90, 0, 0); root.add_child(l)
	var c := Camera3D.new(); root.add_child(c); c.look_at_from_position(Vector3(0, 6, 0.01), Vector3.ZERO)
	for k in CASES:
		var m := ShaderMaterial.new(); var sh := Shader.new(); sh.code = "shader_type spatial;\n" + CASES[k]; m.shader = sh
		m.set_shader_parameter("t", tex)
		if k == "emit_set_color": m.set_shader_parameter("c", Color(0.8, 0.7, 0.55))
		mi.material_override = m
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var im := get_root().get_texture().get_image()
		var px := im.get_pixel(im.get_width() / 2, im.get_height() / 2)
		print("CASE %-15s %.3f %.3f %.3f" % [k, px.r, px.g, px.b])
	quit()
