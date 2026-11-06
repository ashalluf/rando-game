extends SceneTree
## Lists the deco buildings (DecoBoulevard) round a point, for framing stills:
##   godot --headless --path . --script tools/deco_probe.gd -- --spawn=x,z,0,0
## R=metres (default 600), KIND=tower|corner|theatre|apartments|courtyard to filter.
## Each line: kind, palette, name, height, the block, the boulevard it fronts, its front's middle
## (true world), and two EYEs for still_shot.gd: across the boulevard at the far kerb looking at the
## facade (street level), and up the street 40 m off at 8 m (an oblique).
## A census line per kind at the end. Headless is enough: only the plan is read (DecoBoulevard is
## loaded at run time, so the tool compiles before the autoloads exist).
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
	var db: GDScript = load("res://scripts/world/deco_boulevard.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 600.0
	var want := OS.get_environment("KIND")
	var names := ["none", "tower", "corner", "theatre", "apartments", "courtyard"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 70.0) + 2
	var census := {}
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var rect: Rect2 = plan.block(ix, iz).rect
			if rect.get_center().distance_to(c) > reach:
				continue
			var plans: Dictionary = db.call("block_plans", plan, ix, iz)
			for k in plans:
				var lp: Dictionary = plans[k]
				var kind: String = names[int(lp.kind)]
				census[kind] = int(census.get(kind, 0)) + 1
				if want != "" and kind != want:
					continue
				var f: Dictionary = lp.frame
				var a: Vector2 = f.a
				var n: Vector2 = f.n
				var front: Vector2 = load("res://scripts/world/industrial.gd").call("fp", f, float(lp.u_mid), 0.0)
				var road: Array = lp.road
				var rw: float = plan.road_width(road[0], road[1])
				var sw: float = plan.sidewalk_width
				var far: Vector2 = front - n * (sw + rw - 1.5)
				var look: Vector2 = front - far
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var obl: Vector2 = front - n * (sw + rw * 0.5) + a * 40.0
				var look2: Vector2 = front - obl
				var yaw2 := rad_to_deg(atan2(-look2.x, -look2.y))
				var h: float = lp.h
				var pitch := rad_to_deg(atan2(h * 0.45, look.length()))
				print("DECO %s %s \"%s\" h=%.1f w=%.1f d=%.1f corner=%d block=%d,%d road=%s(%.0f m) front=%.1f,%.1f EYE=%.1f,1.7,%.1f,%.0f,%.0f OBLIQUE=%.1f,8,%.1f,%.0f,%.0f" % [
					kind, lp.palette, lp.name, h, lp.w, lp.d, lp.corner, ix, iz, plan.road_name(road[0], road[1]), rw,
					front.x, front.y, far.x, far.y, yaw, pitch, obl.x, obl.y, yaw2, rad_to_deg(atan2(h * 0.4, look2.length()))])
	print("CENSUS ", census)
	quit()
