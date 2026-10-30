extends SceneTree
## Lists the civic buildings (CivicBuildings) for a seed: kind, name, site, frontage x depth and
## EYEs for still_shot.gd (from across the street, and from up and back).
##   godot --headless --path . --script tools/civic/probe.gd [-- --seed=N --radius=M --at=x,z]

func _initialize() -> void:
	await process_frame
	load("res://tools/civic/probe_run.gd").new().call("run", self)
	quit()
