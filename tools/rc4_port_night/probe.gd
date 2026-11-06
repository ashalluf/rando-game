extends SceneTree
## The container terminal at night (PortNight): prints the floods the materials get, and for every
## built port chunk round the spawn its pools, apron pools and halos. Headless, a couple of minutes:
##   godot --headless --path . --script tools/rc4_port_night/probe.gd -- --spawn=3182,6490,101,10
## (Nothing here is named as a type: it compiles before the autoloads exist.)
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 30:
		await process_frame
	var city := current_scene
	var plan = city.get("plan")
	var pn: GDScript = load("res://scripts/world/port_night.gd")
	var src: Array = pn.call("sources", plan)
	print("PORTNIGHT blocks=%d sources=%d enabled=%s" % [(pn.call("port_blocks", plan) as Array).size(), src.size(), str(pn.get("enabled"))])
	for s: Vector4 in src:
		print("  source (%.1f, %.1f, %.1f) reach %.0f" % [s.x, s.y, s.z, s.w])
	for ch in city.get_children():
		var nodes: Variant = ch.get("_mm_nodes")
		if not (nodes is Dictionary) or not (nodes as Dictionary).has("port_pool"):
			continue
		var line := "CHUNK %s level %s:" % [ch.name, str(ch.get("level"))]
		for k: String in ["port_pool", "port_apron_pool", "atmos_glow_halo", "port_mast", "container"]:
			var n: Variant = (nodes as Dictionary).get(k)
			if n is MultiMeshInstance3D:
				line += " %s=%d" % [k, (n as MultiMeshInstance3D).multimesh.instance_count]
		print(line)
		var ap: Variant = (nodes as Dictionary).get("port_apron_pool")
		if OS.get_environment("PN_POOLS") == "1" and ap is MultiMeshInstance3D:
			var mm: MultiMesh = (ap as MultiMeshInstance3D).multimesh
			var wo: Vector3 = root.get_node("/root/WorldState").get("world_offset")
			for i in mini(mm.instance_count, 4):
				print("    apron pool at %s (true world)" % str((ap as Node3D).global_transform * mm.get_instance_transform(i).origin + wo))
			print("    node visible %s aabb %s" % [str((ap as Node3D).is_visible_in_tree()), str((ap as MultiMeshInstance3D).get_aabb())])
	quit()
