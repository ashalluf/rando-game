extends SceneTree
## Compiles the freight line's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/freight/compile.gd

const SCRIPTS := ["res://scripts/world/freight_rail.gd", "res://scripts/world/freight_kit.gd",
	"res://scripts/world/freight_yard.gd", "res://scripts/world/freight_rail_system.gd",
	"res://scripts/world/freight_car_body.gd", "res://scripts/vehicles/freight_stock.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/world/city_plan.gd", "res://scripts/world/macro_map.gd",
	"res://scripts/npc/traffic.gd", "res://scripts/world/city_streamer.gd", "res://scripts/util/sfx.gd", "res://scripts/world/river_build.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	for sh: String in ["res://shaders/freight_track.gdshader", "res://shaders/freight_stock.gdshader"]:
		var shader: Shader = load(sh)
		var m := ShaderMaterial.new()
		m.shader = shader
		print("SHADER %s %s" % [sh, shader.code.length()])
	quit()
