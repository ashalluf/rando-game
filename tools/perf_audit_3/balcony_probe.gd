extends SceneTree
## Where the PropFactory.balcony() nodes are in a loaded city, and whether their building also
## has the facade kit's (docs/HANDOFF.md, the perf-audit-3 section). Headless:
##   godot --headless --path . --script tools/perf_audit_3/balcony_probe.gd -- --spawn=300,528,0,-35,120
func _initialize() -> void:
	root.add_child((load("res://scenes/levels/city.tscn") as PackedScene).instantiate())
	for i in 300:
		await physics_frame
	var rows := {}
	var n := 0
	for node in root.find_children("Balconies", "MultiMeshInstance3D", true, false):
		n += 1
		var b := node.get_parent()
		var ch := b.get_parent()
		while ch and ch.get("level") == null:
			ch = ch.get_parent()
		var kit := b.find_children("Batch_kit_*", "", false, false).size()
		var key := "%s level %s kit nodes %d script %s" % [ch.name if ch else "-", str(ch.get("level")) if ch else "-", mini(kit, 1), (b.get_script() as Script).resource_path.get_file() if b.get_script() else "-"]
		rows[key] = int(rows.get(key, 0)) + (node as MultiMeshInstance3D).multimesh.instance_count
	print("BALCONIES nodes %d" % n)
	for k in rows:
		print("BALCONIES %6d instances  %s" % [rows[k], k])
	quit()
