extends SceneTree
## What ShopfrontDress puts out on a few rows of shops, headless, in seconds:
##   SF_DEBUG=1 godot --headless --path . --script tools/storefront_closeup_2/probe.gd
## N buildings (default 12) from SEED (default 5100, step 71), each built as
## tools/glshot/building_shot.gd builds one (LOT square metres, default 30; HMIN / HMAX, default
## 60 / 90; FINISH), so a seed found here shoots there. Prints each building's kinds (vertex counts
## in its StreetDress by kind) and, with SF_DEBUG=1, every piece with a CAM_POS / CAM_LOOK for
## building_shot.gd 3.5 m out from it.
func _initialize() -> void:
	for i in 3:
		await process_frame
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var n := _int("N", 12)
	var first := _int("SEED", 5100)
	var lot := float(_int("LOT", 30))
	var total := {}
	var tris := 0
	for i in n:
		var b: Node = scene.instantiate()
		b.set("seed", first + i * 71)
		b.set("lot_size", Vector2(lot, lot))
		b.set("min_height", float(_int("HMIN", 60)))
		b.set("max_height", float(_int("HMAX", 90)))
		if OS.get_environment("FINISH") != "":
			(b.get("finish_options") as Array).assign([_int("FINISH", 0)])
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
		for it: Array in b.get_meta("sf_dress_log", []):
			var p: Vector3 = it[1]
			var nn: Vector3 = it[2]
			var side := Vector3.UP.cross(nn) * 1.2
			var eye := p + nn * 3.5 + side + Vector3(0.0, 0.0, 0.0)
			eye.y = 1.6
			print("  ITEM %s at %s  CAM_POS=%.2f,%.2f,%.2f CAM_LOOK=%.2f,%.2f,%.2f" % [it[0], p, eye.x, eye.y, eye.z, p.x, p.y + 0.4, p.z])
		b.free()
	print("PROBE total %s, %d triangles in %d StreetDress meshes" % [total, tris, n])
	quit()


func _int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
