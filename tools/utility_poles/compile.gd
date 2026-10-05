extends SceneTree
## Compiles UtilityPoles and its shaders and prints each hardware mesh's triangles (seconds,
## headless):
##   godot --headless --path . --script tools/utility_poles/compile.gd
func _initialize() -> void:
	var up: GDScript = load("res://scripts/world/utility_poles.gd")
	for p in ["res://shaders/utility_pole.gdshader", "res://shaders/utility_wire.gdshader"]:
		var sh: Shader = load(p)
		print("SHADER %s: %d uniforms" % [p, sh.get_shader_uniform_list().size()])
	var t0 := Time.get_ticks_usec()
	if up == null or not up.can_instantiate():
		quit(1)
		return
	var counts: Dictionary = up.call("triangle_counts")
	print("UP meshes built in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	for k: String in counts:
		print("UP %-7s %5d triangles" % [k, counts[k]])
	quit()
