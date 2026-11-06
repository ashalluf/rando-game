extends SceneTree
## Surfaces, distinct materials and LOD-0 triangles of the scanned plant models (perf-audit-4's
## plant merge): godot --headless --path . --script tools/perf_audit_4/surf_probe.gd
## (PLANT_MERGE=0 for the before).
func _initialize() -> void:
	var pf = load("res://scripts/world/prop_factory.gd")
	var specs := [["model_grass_clump", pf.GRASS_CLUMPS.size()], ["model_flower", pf.FLOWERS.size()],
		["model_bush", pf.BUSHES.size()], ["model_plant", pf.PLANTS.size()], ["model_scrub", 5], ["model_grass_tuft", 5]]
	for spec in specs:
		for v in int(spec[1]):
			var m: Mesh = pf.call(spec[0], v)
			var mats := {}
			var tris := 0
			for s in m.get_surface_count():
				mats[m.surface_get_material(s)] = true
				tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print("PLANT %s %d surfaces %d mats %d tris %d" % [spec[0], v, m.get_surface_count(), mats.size(), tris])
	quit()
