extends SceneTree
## Parses shaders headless and says which fail: Godot's shader compiler runs on load even under the
## dummy renderer (a SHADER ERROR line names the problem), although no GPU compile happens there.
##
##   godot --headless --path . --script tools/shader_check.gd [-- res://shaders/a.gdshader ...]
##
## With no paths it checks the building shaders. A shader that fails falls back to blank white in
## the game, which looks like a missing texture, not like an error - and the headless smoke test
## does not notice it.

func _initialize() -> void:
	var paths := Array(OS.get_cmdline_user_args())
	if paths.is_empty():
		paths = ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader"]
	for p: String in paths:
		var sh: Shader = load(p)
		var m := ShaderMaterial.new()
		m.shader = sh
		print("SHADER_CHECK %s: %d uniforms (a SHADER ERROR above this line means it failed)" % [p, sh.get_shader_uniform_list().size()])
	quit()
