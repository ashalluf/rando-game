extends SceneTree
## Compiles the rain crowd's scripts once the autoloads exist, builds every umbrella step and a
## hood per crowd rig, and prints their triangle counts and build times (seconds, headless):
##   godot --headless --path . --script tools/rain_crowd/compile.gd

const SCRIPTS := ["res://scripts/npc/rain_gear.gd", "res://scripts/npc/rain_crowd.gd",
	"res://scripts/npc/pedestrian.gd", "res://scripts/world/weather.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	var sh: Shader = load("res://shaders/rain_gear.gdshader")
	var m := ShaderMaterial.new()
	m.shader = sh
	print("SHADER rain_gear %d uniforms" % sh.get_shader_uniform_list().size())
	var gear: GDScript = load("res://scripts/npc/rain_gear.gd")
	for k in [0, 1]:
		var line := "UMBRELLA kind %d:" % k
		for st in 7:
			var t := Time.get_ticks_usec()
			var mesh: ArrayMesh = gear.call("umbrella", k, st)
			var tris := mesh.surface_get_array_index_len(0) / 3
			line += " %d tris %.1f ms;" % [tris, (Time.get_ticks_usec() - t) / 1000.0]
		print(line)
	for path: String in ["res://assets/models/crowd_m.glb", "res://assets/models/crowd_o.glb", "res://assets/models/crowd_a.glb"]:
		var t := Time.get_ticks_usec()
		var mesh: ArrayMesh = gear.call("hood", path)
		print("HOOD %s %d tris %.1f ms aabb %s" % [path.get_file(), mesh.surface_get_array_index_len(0) / 3,
			(Time.get_ticks_usec() - t) / 1000.0, mesh.get_aabb()])
	quit()
