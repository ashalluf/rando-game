extends SceneTree
## Lists the rooftop pieces (Rooftops) round a point of the default seed's city, with an EYE for
## tools/glshot/still_shot.gd framed on each, from the far city's capture of each block (what the
## LOD ring and the far city draw is what the near building builds):
##
##   godot --headless --path . --script tools/rooftops/find.gd -- --at=2800,100 --radius=700
##
## KIND=helipad|pool|garden|penthouse|mast|bmu filters. Headless, a few seconds a block.

func _initialize() -> void:
	await process_frame
	load("res://tools/rooftops/find_run.gd").new().call("run", self)
