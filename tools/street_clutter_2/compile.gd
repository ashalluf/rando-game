extends SceneTree
func _initialize() -> void:
	for p in ["res://scripts/world/street_clutter_2.gd", "res://scripts/world/building.gd", "res://scripts/world/city_chunk.gd"]:
		var s = load(p)
		print("LOADED ", p, " ", s != null)
	quit()
