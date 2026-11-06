extends SceneTree
## Lists the places of worship of a seed (Worship.for_cell over the basin): kind, name, site,
## and EYEs for tools/glshot/still_shot.gd - one from across the street at eye height, one
## raised three-quarter view. Headless, seconds.
##   godot --headless --path . --script tools/worship/probe.gd [-- --seed=N --kind=mission --near=x,z]

func _initialize() -> void:
	await process_frame
	load("res://tools/worship/probe_run.gd").new().call("run", self)
	quit()
