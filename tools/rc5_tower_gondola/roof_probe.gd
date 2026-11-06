extends SceneTree
## Lists the building parts (far city capture boxes) round a point of the default seed's city,
## tallest roof first, for framing the tower_gondola refcam from a lower neighbour's roof:
##   godot --headless --path . --script tools/rc5_tower_gondola/roof_probe.gd -- --at=2290,230 --radius=140

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_tower_gondola/roof_probe_run.gd").new().call("run", self)
