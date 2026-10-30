extends SceneTree
## Lists the outdoor dining parklets (Parklets) round a point, for framing stills (seconds to a
## minute, headless): builds the FULL chunks of the blocks within R metres and prints each
## parklet, its shop's room, its diners and an EYE for still_shot.gd on the pavement opposite.
##   godot --headless --path . --script tools/parklets/probe.gd -- --spawn=x,z,0,0 [--hour=13]
## R=metres (default 300). Also prints the kit's meshes' triangle counts.

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 13.0
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
	var pk: GDScript = load("res://scripts/world/parklets.gd")
	var kit: GDScript = load("res://scripts/world/parklet_kit.gd")
	pk.set("force_hour", hour)
	var meshes: Array = [kit.call("deck", 6.0), kit.call("deck", 8.0), kit.call("deck", 10.0),
		kit.call("bistro_set", false, true, false), kit.call("bistro_set", true, true, true), kit.call("bistro_set", false, false, false),
		kit.call("umbrella", true), kit.call("umbrella", false)]
	for m: Mesh in meshes:
		var n := 0
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("MESH tris=%d" % n)
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 300.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 1
	var found := 0
	var rooms := 0
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
			for b in ch.get_children():
				if b.get("shop_fronts") != null:
					for f: Array in b.shop_fronts:
						if int(f[3]) == 2 or int(f[3]) == 3:
							rooms += 1
			var diners := 0
			var waiters := 0
			for n in ch.get_children():
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("parklet_diner.gd"):
					if int(n.get("role")) == 0:
						diners += 1
					else:
						waiters += 1
			for p: Dictionary in ch.get_meta("parklets", []):
				var at: Vector2 = p.c
				var dir: Vector2 = p.dir
				var o: Vector2 = p.out
				var w := Vector3(at.x, 0.0, at.y)
				var eye := at + o * 9.0 + dir * 6.0
				var look := (at + o * 1.0) - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("PARKLET block=%d,%d face=%d room=%s len=%.0f at=%.1f,%.1f diners=%d waiters=%d build=%.0fms EYE=%.1f,1.7,%.1f,%.0f,-8" % [
					ix, iz, int(p.face), "cafe" if int(p.room) == 2 else "restaurant", float(p.length), w.x, w.z, diners, waiters, ms, eye.x, eye.y, yaw])
				found += 1
			ch.get_parent().remove_child(ch)
			ch.free()
	print("FOUND %d parklets on %d chunks (%d cafe/restaurant fronts)" % [found, chunks, rooms])
	quit()
