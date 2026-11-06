extends Node
## Compiles the refinery's scripts and shaders in seconds (SCRIPT ERROR / SHADER ERROR otherwise):
##   godot --headless --path . res://tools/refinery/compile.tscn
func _ready() -> void:
	for p in ["res://scripts/world/refinery.gd", "res://scripts/world/refinery_kit.gd", "res://scripts/world/refinery_far.gd",
			"res://scripts/world/refinery_cover.gd", "res://tests/refinery_checks.gd", "res://scripts/world/city_streamer.gd",
			"res://scripts/world/landmarks.gd", "res://scripts/world/skyline.gd"]:
		var s := load(p) as Script
		print("COMPILE ", p, " ", s != null and s.can_instantiate())
	for p in ["res://shaders/refinery.gdshader", "res://shaders/refinery_flame.gdshader", "res://shaders/refinery_plume.gdshader"]:
		var m := ShaderMaterial.new()
		m.shader = load(p)
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = m
		add_child(mi)
		print("SHADER ", p, " ", m.shader != null)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
