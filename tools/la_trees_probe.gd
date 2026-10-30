extends SceneTree
## Finds the code-built Los Angeles trees (LaTrees) round a point, for framing stills:
##   godot --headless --path . --script tools/la_trees_probe.gd -- --spawn=x,z,0,0
## MODE=street (default): blocks whose kerb rows swap species, with an EYE on the pavement looking
## down the row; MODE=cypress: houses that get a cypress pair, an EYE in the street facing the
## door; MODE=row: the freeway's right-of-way tree row, an EYE beside it. R=metres (default 600),
## SPECIES=n to filter the street mode. Headless is enough: only the plan is read.
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
	var la: GDScript = load("res://scripts/world/la_trees.gd")
	var hk: GDScript = load("res://scripts/world/house_kit.gd")
	var yf: GDScript = load("res://scripts/world/yard_fill.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 600.0
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "street"
	var want := int(OS.get_environment("SPECIES")) if OS.get_environment("SPECIES") != "" else -1
	var names: Array = la.get("NAMES")
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 60.0) + 2
	var found := 0
	if mode == "chunk":
		# K=ix,iz: build that block FULL and list its batches.
		var kk := OS.get_environment("K").split(",")
		var ch = current_scene.call("_new_chunk", Vector2i(kk[0].to_int(), kk[1].to_int()), 0)
		ch.call("build")
		for n in ch.get_children():
			if n is MultiMeshInstance3D and String(n.name).begins_with("Batch_"):
				print("BATCH %s %d" % [n.name, (n as MultiMeshInstance3D).multimesh.instance_count])
		print("META cypress=%d accents=%d" % [int(ch.get_meta("la_cypress", 0)), int(ch.get_meta("la_accents", 0))])
		for e: Array in ch.get_meta("la_at", []):
			print("AT %s %.1f,%.1f" % [names[int(e[0])], (e[1] as Vector3).x, (e[1] as Vector3).z])
		for p: Vector3 in ch.get_meta("la_cypress_at", []):
			print("CYPRESS_AT %.1f,%.1f" % [p.x, p.z])
		quit()
		return
	if mode == "row":
		var fw = plan.macro.freeway
		for s in fw.segments_in(Rect2(c - Vector2(reach, reach), Vector2(reach, reach) * 2.0)):
			var a: Vector2 = s.a
			var b: Vector2 = s.b
			var dir := (b - a).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var p := (a + b) * 0.5 + nrm * (float(s.width) * 0.5 + 8.5)
			var eye := p + nrm * 14.0 - dir * 18.0
			var look := p + dir * 10.0 - eye
			print("ROW route=%s at=%.1f,%.1f EYE=%.1f,3.0,%.1f,%.0f,6" % [str(s.get("route", "")), p.x, p.y, eye.x, eye.y, rad_to_deg(atan2(-look.x, -look.y))])
			found += 1
			if found > 30:
				break
		print("FOUND ", found)
		quit()
		return
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			if mode == "street":
				var sp: int = la.call("street_species", plan, ix, iz)
				if sp < 0 or (want >= 0 and sp != want) or block.kind != 0:
					continue
				# On the -z pavement near the west corner, looking east along the row.
				var eye := Vector2(rect.position.x + 6.0, rect.position.y + 2.5)
				print("STREET %s district=%d block=%d,%d rect=%s EYE=%.1f,1.7,%.1f,-90,4" % [names[sp], int(block.district), ix, iz, str(rect), eye.x, eye.y])
				found += 1
			elif mode == "cypress":
				var district: int = block.district
				if not (district in (hk.get("DISTRICTS") as Array)) or block.kind != 0:
					continue
				var lots: Array = plan.lots(ix, iz)
				lots.append_array(hk.call("extra_lots", plan, ix, iz))
				for lot: Dictionary in lots:
					var h: Dictionary = hk.call("plan_house", plan, ix, iz, lot, district)
					var odds: Dictionary = la.get("CYPRESS_ODDS")
					if float(h.door_v) < 2.6 or la.call("_h01", [plan.seed, int(h.seed), "la_cypress"]) >= float(odds.get(int(h.style), 0.0)):
						continue
					var f: Dictionary = h.f
					var door: Vector2 = yf.call("_fp", f, float(h.door_u), 0.0)
					var out: Vector2 = -(f.v as Vector2)
					var eye: Vector2 = door + out * 9.0 + (f.u as Vector2) * 3.0
					var look: Vector2 = door - eye
					print("CYPRESS style=%d block=%d,%d door=%.1f,%.1f EYE=%.1f,1.7,%.1f,%.0f,8" % [int(h.style), ix, iz, door.x, door.y, eye.x, eye.y, rad_to_deg(atan2(-look.x, -look.y))])
					found += 1
	print("FOUND ", found)
	quit()
