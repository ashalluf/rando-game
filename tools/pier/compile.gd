extends SceneTree
## Compiles the pier park's scripts once the autoloads exist, builds the park near and far into a
## bare node and prints what it cost (triangles, nodes, shapes). Headless, seconds:
##   godot --headless --path . --script tools/pier/compile.gd

const SCRIPTS := ["res://scripts/world/pier_mesh.gd", "res://scripts/world/pier_park.gd",
	"res://scripts/world/ferris_wheel.gd", "res://scripts/world/pier_coaster.gd", "res://scripts/world/pier_carousel.gd",
	"res://scripts/world/pier_ride_body.gd", "res://scripts/npc/pier_goer.gd", "res://scripts/world/landmarks.gd",
	"res://scripts/world/city_chunk.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	# Named classes only past the first frame (the autoloads): the body is its own script.
	await load("res://tools/pier/compile_body.gd").new().run(self)
	quit()
