extends SceneTree
## Parses every shader in shaders/ (plus any path given after --) and prints the result, so a
## typo in a .gdshader is caught in seconds instead of by a six-minute render that comes back
## blank white. Godot parses a Shader when its code is set, so this needs no renderer.
##
##   godot --headless --path . --script tools/shader_check.gd -- shaders/macro_ground.gdshader
func _initialize() -> void:
	var paths: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".gdshader"):
			paths.append("res://" + arg.trim_prefix("res://"))
	if paths.is_empty():
		for f in DirAccess.get_files_at("res://shaders"):
			if f.ends_with(".gdshader"):
				paths.append("res://shaders/" + f)
	for p in paths:
		var sh := Shader.new()
		sh.code = FileAccess.get_file_as_string(p)
		var names := sh.get_shader_uniform_list()
		print("OK ", p, " uniforms=", names.size())
	quit()
