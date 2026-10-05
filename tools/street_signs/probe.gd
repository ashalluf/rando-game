extends SceneTree
## Lists the junctions round a point with their kind, district and street names, plus an EYE for
## still_shot.gd on the pavement looking at the +X +Z corner (where the name blades always are):
##   godot --headless --path . --script tools/street_signs/probe.gd -- --spawn=x,z,0,0
## R=metres (default 500), KIND=plain|stop|signals|roundabout to filter, SCHOOLS=1 lists the
## school blocks in reach too. Headless: only the plan is read.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 500.0
	var want := OS.get_environment("KIND")
	var cpk: Dictionary = (load("res://scripts/world/city_plan.gd") as GDScript).get_script_constant_map()
	var mmk: Dictionary = (load("res://scripts/world/macro_map.gd") as GDScript).get_script_constant_map()
	var kinds := ["plain", "stop", "signals", "roundabout"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 60.0) + 2
	var found := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var inter: Dictionary = plan.intersection(ix + 1, iz + 1)
			var pos: Vector2 = inter.pos
			if pos.distance_to(c) > reach:
				continue
			var block: Dictionary = plan.block(ix, iz)
			if OS.get_environment("SCHOOLS") == "1" and int(block.kind) == int(cpk.BlockKind.SCHOOL):
				print("SCHOOL block=%d,%d rect=%s grounds=%s" % [ix, iz, str(block.rect), str(block.get("grounds", ""))])
			var kind: String = kinds[int(inter.kind)]
			if want != "" and kind != want:
				continue
			if plan.zone_at(pos) != int(mmk.Zone.CITY) or plan.junction_closed(ix + 1, iz + 1):
				continue
			var size: Vector2 = inter.size
			var corner: Vector2 = pos + size * 0.5 + Vector2(1.4, 1.4)
			var eye: Vector2 = corner + Vector2(-7.0, 9.0)
			var look: Vector2 = corner - eye
			var yaw := rad_to_deg(atan2(-look.x, -look.y))
			print("JUNCTION %s %s block=%d,%d at=%.1f,%.1f size=%.0fx%.0f x=%s z=%s EYE=%.1f,1.7,%.1f,%.0f,6" % [
				kind, cpk.DISTRICT_NAMES[plan.district_at(pos)], ix, iz, pos.x, pos.y, size.x, size.y,
				plan.road_name(0, ix + 1), plan.road_name(1, iz + 1), eye.x, eye.y, yaw])
			found += 1
	print("FOUND ", found)
	# SIGNS=ix,iz builds that block's FULL chunk and prints its block signs (StreetSigns.debug).
	if OS.get_environment("SIGNS") != "":
		var k := OS.get_environment("SIGNS").split(",")
		var ss: GDScript = load("res://scripts/world/street_signs.gd")
		ss.set("debug", true)
		var full: int = ((load("res://scripts/world/city_chunk.gd") as GDScript).get_script_constant_map().Level as Dictionary).FULL
		var chunk = current_scene.call("_new_chunk", Vector2i(k[0].to_int(), k[1].to_int()), full)
		chunk.call("build")
		# What stands within 2.5 m of each block sign once the chunk is finished (by batch node).
		for r: Dictionary in chunk.get("prop_records"):
			if not String(r.id).begins_with("ssign_"):
				continue
			var at: Vector3 = r.position
			for nd in chunk.get_children():
				if nd is MultiMeshInstance3D:
					var xs: Array = chunk.get_meta("ss_debug_all", {}).get(String(nd.name).trim_prefix("Batch_"), [])
					for x: Transform3D in xs:
						if Vector2(x.origin.x - at.x, x.origin.z - at.z).length() < 2.5 and not String(nd.name).begins_with("Batch_ss_"):
							print("NEAR %s %s %.2f" % [r.id, nd.name, Vector2(x.origin.x - at.x, x.origin.z - at.z).length()])
	quit()
