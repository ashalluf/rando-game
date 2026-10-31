extends SceneTree
## The far city's size and cost: builds the whole tier (Skyline) the way the loading screen does
## and prints how long it took, how much memory it holds, and what it is made of - tiles, box
## instances by kind (facade parts, plain boxes, plates, decks), planting and estates, and the
## triangles one frame would submit if every instance were drawn (the counters a render reads).
##
##   godot --headless --path . --script tools/far_census.gd [-- --eye=x,z --radius=m]
##
## Headless is right here: this measures the CPU build and the instance data, not the GPU (and
## MultiMesh instance data reads back empty under the dummy renderer, so it counts the arrays the
## tier kept, never the MultiMeshes).

func _initialize() -> void:
	# The work lives in far_census_run.gd, compiled only now that the autoloads are in.
	await process_frame
	var runner: RefCounted = load("res://tools/far_census_run.gd").new()
	runner.call("run", self)
