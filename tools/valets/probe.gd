extends SceneTree
## Lists the valet stands (Valets) round a point, for framing stills (a minute, headless): builds
## the FULL chunks of the blocks within R metres and prints each stand (hotel or restaurant, its
## zone, how many valets came) with an EYE for still_shot.gd on the pavement up the kerb.
##   godot --headless --path . --script tools/valets/probe.gd -- --spawn=x,z,0,0 [--hour=20]
## R=metres (default 300). Also prints the kit's meshes' triangle counts.

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 20.0
	var spawn_given := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
			spawn_given = true
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	if not spawn_given and plan.macro:
		c = plan.macro.downtown_center
	var vs: GDScript = load("res://scripts/world/valets.gd")
	var kit: GDScript = load("res://scripts/world/valet_kit.gd")
	vs.set("force_hour", hour)
	for m: Mesh in [kit.call("podium", 0), kit.call("key_box"), kit.call("sign", 0), kit.call("cone"), kit.call("umbrella_base")]:
		print("MESH tris=%d" % ((m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3))
	var cs: GDScript = load("res://scripts/world/civic_sites.gd")
	print("LANDMARK HOTEL anchor ", cs.call("anchor", "live_hotel"), " block ", plan.block_index_at(cs.call("anchor", "live_hotel")))
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 300.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 1
	var found := 0
	var chunks := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			if plan.zone_at(rect.get_center()) != 0:
				continue
			var ch = city.call("_new_chunk", Vector2i(ix, iz), 0)
			var t0 := Time.get_ticks_usec()
			ch.build()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			chunks += 1
			for s: Dictionary in ch.get_meta("valet_stands", []):
				var pod: Vector2 = s.podium
				var trav: Vector2 = s.trav
				var o: Vector2 = s.out
				var eye: Vector2 = pod - trav * 16.0 + o * 0.2 - o * 2.0
				var look: Vector2 = (pod + trav * 2.0 + o * 3.0) - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var n_valets := 0
				if s.has("node"):
					n_valets = (s.node.get("valets") as Array).size()
				print("VALET block=%d,%d face=%d %s op=%d zone=%.0f..%.0f podium=%.1f,%.1f valets=%d build=%.0fms EYE=%.1f,1.7,%.1f,%.0f,-6" % [
					ix, iz, int(s.face), ("landmark hotel" if s.landmark else "hotel") if s.hotel else "restaurant", int(s.op), s.zone.x, s.zone.y, pod.x, pod.y, n_valets, ms, eye.x, eye.y, yaw])
				found += 1
			ch.get_parent().remove_child(ch)
			ch.free()
	print("FOUND %d stands on %d chunks" % [found, chunks])
	quit()
