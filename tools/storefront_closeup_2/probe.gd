extends SceneTree
## What ShopfrontDress puts out on a few rows of shops, headless, in seconds:
##   godot --headless --path . --script tools/storefront_closeup_2/probe.gd
## (N buildings, default 12; SEED the first seed.) Prints each building's kinds (vertex counts in
## its StreetDress by kind) and footprints; the totals at the end.
func _initialize() -> void:
	for i in 3:
		await process_frame
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 12
	var first := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 5100
	var total := {}
	var tris := 0
	for i in n:
		var b: Node = scene.instantiate()
		b.set("seed", first + i * 71)
		b.set("lot_size", Vector2(26.0, 20.0))
		b.set("min_height", 12.0)
		b.set("max_height", 18.0)
		b.set("allow_storefront", true)
		root.add_child(b)
		var mi := b.get_node_or_null("StreetDress") as MeshInstance3D
		var kinds := {}
		if mi:
			var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
			for c: Color in arr[Mesh.ARRAY_COLOR]:
				var k := int(floor(c.a * 16.0 + 0.5))
				kinds[k] = int(kinds.get(k, 0)) + 1
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		for k: int in kinds:
			total[k] = int(total.get(k, 0)) + int(kinds[k])
		print("PROBE seed %d finish %d: kinds %s spots %d" % [b.get("seed"), b.get("finish"), kinds, (b.get_meta("sf_dress", []) as Array).size()])
		b.free()
	print("PROBE total %s, %d triangles in %d StreetDress meshes" % [total, tris, n])
	quit()
