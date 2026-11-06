extends SceneTree
## The gate's kit meshes (RcPortGate) built and counted, headless, seconds:
##   godot --headless --path . --script tools/rc5_port_gate/mesh_probe.gd
## (Loaded by path: the classes compile before the autoloads exist.)
func _initialize() -> void:
	await process_frame
	var kit: GDScript = load("res://scripts/world/port_life_kit.gd")
	var rc: GDScript = load("res://scripts/world/rc5_port_gate.gd")
	for pair in [["booth", kit.booth_mesh()], ["canopy", kit.canopy_mesh(8)], ["portal", kit.portal_mesh(8)], ["barrier", rc.barrier_mesh()]]:
		var m: ArrayMesh = pair[1]
		var tris := 0
		for s in m.get_surface_count():
			tris += m.surface_get_array_index_len(s) / 3
		print("RC5_GATE_MESH %s tris=%d aabb=%s enabled=%s" % [pair[0], tris, m.get_aabb(), rc.get("enabled")])
	var seed := 1337
	for i in 8:
		var row := ""
		for slot in 2:
			var h := absi(hash([seed, "gate_truck", i, slot]))
			row += " slot%d=%d%s" % [slot, h % 100, "(bobtail)" if (h / 100) % 5 == 0 else ""]
		print("RC5_GATE_TRUCK lane %d%s" % [i, row])
	quit()
