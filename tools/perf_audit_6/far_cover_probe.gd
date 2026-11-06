extends SceneTree
## How much of the far city (Skyline) is drawn collapsed: tiles that a chunk ring covers only in
## part keep every instance, the covered blocks' collapsed to zero in the vertex shader (they still
## cost vertices and count as triangles). Builds the far city round an eye the way the loading
## screen does, takes the chunk window CityStreamer would ask for there (FULL within two blocks /
## full_reach, LOD within seven / lod_reach) and splits each tile's triangles into drawn, collapsed
## in a shown tile (waste) and hidden (a whole tile covered).
##
##   godot --headless --path . --script tools/perf_audit_6/far_cover_probe.gd -- --eye=x,z
##
## No frustum: the numbers are the whole ring round the eye, an upper bound for any one view.

func _initialize() -> void:
	await process_frame
	var runner: RefCounted = load("res://tools/perf_audit_6/far_cover_probe_run.gd").new()
	await runner.call("run", self)
	quit()
