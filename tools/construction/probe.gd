extends SceneTree
## Lists the building sites round a point, for framing stills and checking the shares:
##   godot --headless --path . --script tools/construction/probe.gd -- --spawn=x,z [R=metres]
## TOWER lines: the block, the lot, storeys built / planned, the crane's ring height and jib, and
## an EYE from the street and one from the air for still_shot.gd. ROAD lines: the closure and an
## EYE on the pavement upstream. HOUSES: how many house lots in range are frames. Headless: only
## the plan is read (Construction is loaded at run time, after the autoloads).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(2800.0, 102.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var con: GDScript = load("res://scripts/world/construction.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 800.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 60.0) + 2
	var towers := 0
	var roads := 0
	var houses := 0
	var frames := 0
	var blocks := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			blocks += 1
			var t: Dictionary = con.call("tower_site", plan, ix, iz)
			if not t.is_empty():
				towers += 1
				var foot: Rect2 = t.foot
				var cr: Dictionary = t.crane
				var fc := foot.get_center()
				var g: float = plan.macro.relief_at(fc) if plan.macro.has_method("relief_at") else 0.0
				var street: Array = t.street
				var sd: int = street[0] if not street.is_empty() else 0
				var dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
				var out: Vector2 = dirs[sd]
				var cell: Rect2 = t.cell
				var edge := fc + out * (absf(out.x) * cell.size.x * 0.5 + absf(out.y) * cell.size.y * 0.5)
				var eye := edge + out * 14.0 + Vector2(out.y, -out.x) * 18.0
				var look := fc - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var air := fc + out * 160.0 + Vector2(out.y, -out.x) * 90.0
				var la := fc - air
				var ayaw := rad_to_deg(atan2(-la.x, -la.y))
				print("TOWER block=%d,%d lot=%d at=%.1f,%.1f size=%.0fx%.0f built=%d/%d clad=%d top=%.1f ring=%.0f jib=%.0f street=%s EYE=%.1f,%.1f,%.1f,%.0f,22 AIR=%.1f,%.1f,%.1f,%.0f,-18" % [
					ix, iz, int(t.seed), fc.x, fc.y, foot.size.x, foot.size.y, int(t.built), int(t.total), int(t.clad), float(t.top),
					float(cr.ring), float(cr.jib), str(street), eye.x, 1.7 + g, eye.y, yaw, air.x, g + float(cr.ring) * 0.8 + 40.0, air.y, ayaw])
			for rw: Dictionary in con.call("road_works", plan, ix, iz):
				roads += 1
				var up: float = float(rw.a) - 14.0 if int(rw.dir) > 0 else float(rw.b) + 14.0
				var mid: float = (float(rw.a) + float(rw.b)) * 0.5
				var pe: Vector2 = con.call("cl_point", rw, up, -2.8)
				var pm: Vector2 = con.call("cl_point", rw, mid, 0.0)
				var lk := pm - pe
				var g2: float = plan.macro.relief_at(pe) if plan.macro.has_method("relief_at") else 0.0
				print("ROAD block=%d,%d axis=%d road=%d side=%d %.0f..%.0f lane=%.1f EYE=%.1f,%.1f,%.1f,%.0f,-8" % [ix, iz, int(rw.axis), int(rw.index),
					int(rw.side), float(rw.a), float(rw.b), float(rw.lane), pe.x, 1.9 + g2, pe.y, rad_to_deg(atan2(-lk.x, -lk.y))])
			if int(block.district) in [plan.District.SUBURBS, plan.District.BEACHTOWN]:
				for lot: Dictionary in plan.lots(ix, iz):
					if lot.yard:
						continue
					houses += 1
					if con.call("house_site", plan, lot):
						frames += 1
						if OS.get_environment("HOUSES") == "1":
							var lc: Vector2 = lot.center
							print("HOUSE block=%d,%d at=%.1f,%.1f" % [ix, iz, lc.x, lc.y])
	print("BLOCKS %d TOWERS %d ROADWORKS %d HOUSES %d FRAMES %d" % [blocks, towers, roads, houses, frames])
	quit()
