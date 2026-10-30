extends SceneTree
## Lists the night life (NightLife) round a point, for framing stills (a minute, headless): builds
## the FULL chunks of the blocks within R metres at the hour and prints each venue (kind, name,
## line, people), each premiere's searchlights, and an EYE for still_shot.gd on the pavement.
##   godot --headless --path . --script tools/nightlife/probe.gd -- --spawn=x,z,0,0 [--hour=22.5]
## R=metres (default 300). NIGHTLIFE_ODDS=1 makes every candidate shop a venue;
## NIGHTLIFE_PREMIERE=1 puts tonight's premieres and openings on. PALACES=1 lists every Broadway
## palace with an EYE across the avenue. Also prints the kit's meshes' triangle counts.

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 22.5
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
	var nl: GDScript = load("res://scripts/world/nightlife.gd")
	var kit: GDScript = load("res://scripts/world/nightlife_kit.gd")
	nl.set("force_hour", hour)
	for m: Mesh in kit.call("warm"):
		var n := 0
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("MESH tris=%d" % n)
	if OS.get_environment("PALACES") == "1":
		var bw: GDScript = load("res://scripts/world/broadway.gd")
		for p: Dictionary in bw.call("palaces", plan):
			var lot: Dictionary = p.lot
			var lc: Vector2 = lot.center
			var side := int(p.side)
			var ax: float = bw.call("avenue_x")
			var eye := Vector2(ax - float(side) * 8.0, lc.y - 14.0)
			var look := Vector2(lc.x, lc.y) - eye
			print("PALACE %s num=%d block=%s at=%.1f,%.1f premiere_tonight=%s EYE=%.1f,1.7,%.1f,%.0f,8" % [
				(p.spec as Dictionary).name, int((p.spec as Dictionary).num), str(p.block), lc.x, lc.y,
				str(nl.call("premiere", plan.seed, int((p.spec as Dictionary).num), 0, hour)), eye.x, eye.y, rad_to_deg(atan2(-look.x, -look.y))])
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 300.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 1
	var found := 0
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
			var goers := {}
			for n in ch.get_children():
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("night_goer.gd"):
					var r := int(n.get("role"))
					goers[r] = int(goers.get(r, 0)) + 1
			var beams := 0
			var hb: Node = ch.get_node_or_null("NightLife")
			if hb:
				for n in hb.get_children():
					if String(n.name).begins_with("SkyBeam"):
						beams += 1
			for v: Dictionary in ch.get_meta("nightlife", []):
				var door: Vector2 = v.door
				var o: Vector2 = v.out
				var al: Vector2 = v.along
				var eye := door + o * (float(v.kerb) + 5.0) + al * (float(v.run) * 0.5 + 9.0)
				var look := (door + al * float(v.run) * 0.35) - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("VENUE block=%d,%d %s '%s' at=%.1f,%.1f run=%.1f kerb=%.1f open=%s line=%d EYE=%.1f,1.7,%.1f,%.0f,4" % [
					ix, iz, "club" if int(v.kind) == 1 else "bar", String(v.name), door.x, door.y, float(v.run), float(v.kerb),
					str(v.open), (v.members as Array).size(), eye.x, eye.y, yaw])
				found += 1
			for n in ch.get_children():
				if n is MultiMeshInstance3D and String(n.name).begins_with("Batch_nl_"):
					var mm: MultiMesh = n.multimesh
					print("BATCH %s n=%d vis=%s range=%.0f cast=%d first=%s" % [n.name, mm.instance_count, str(n.visible), n.visibility_range_end, n.cast_shadow, str(mm.get_instance_transform(0).origin) if mm.instance_count > 0 else "-"])
			var holder: Node = ch.get_node_or_null("NightLife")
			if holder:
				var names: Array = []
				for n in holder.get_children():
					names.append(String(n.name))
				print("HOLDER %d,%d %s" % [ix, iz, str(names)])
			if beams > 0 or not goers.is_empty():
				print("CHUNK %d,%d build=%.0fms people=%s beams=%d" % [ix, iz, ms, str(goers), beams])
			ch.get_parent().remove_child(ch)
			ch.free()
	print("VENUES %d" % found)
	quit()
