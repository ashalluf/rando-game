extends SceneTree
## Prints LandmarkRoofs' plan for every downtown tower: penthouses, pieces by kind, duct runs,
## triangles, and the world point of each roof (an EYE to look at it). Headless, seconds:
##   godot --headless --path . --script tools/landmark_roofs/probe.gd

func _initialize() -> void:
	await process_frame
	var LD = load("res://scripts/world/landmark_downtown.gd")
	var LR = load("res://scripts/world/landmark_roofs.gd")
	var total := 0
	for id: String in LD.TOWERS:
		var p: Dictionary = LR.plan(id)
		if p.pent.is_empty():
			print("ROOF %s: none" % id)
			continue
		var kinds := [0, 0, 0]
		for pc: Array in p.pieces:
			kinds[int(pc[0])] += 1
		var m: ArrayMesh = LR.mesh(id)
		var tris: int = m.surface_get_array_index_len(0) / 3
		total += tris
		var a: Vector2 = LD.anchor(id)
		var pe: Array = p.pent[0]
		print("ROOF %s: %d penthouses, rtu %d fan %d tower %d, ducts %d, %d tris, penthouse at local %s (anchor %s)" % [id, p.pent.size(), kinds[0], kinds[1], kinds[2], p.ducts.size(), tris, pe[0], a])
	print("ROOF total tris %d" % total)
	quit()
