extends SceneTree
## Lists the tall pole signs (BoulevardSigns.plan_poles) round a point, for framing stills:
##   godot --headless --path . --script tools/sign_probe.gd -- --spawn=x,z,0,0
## R=metres (default 600), KIND=tenant|motel|liquor|checks|tire to filter. Each line: kind, the
## block and face, the pole's true-world foot and two EYEs for still_shot.gd: one down the
## pavement 18 m off looking at the sign, one close up under it. Also counts the lamp-banner
## boulevards. Headless is enough: only the plan is read.
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
	var bs: GDScript = load("res://scripts/world/boulevard_signs.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 600.0
	var want := OS.get_environment("KIND")
	var names := ["tenant", "motel", "liquor", "checks", "tire"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	var found := {}
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			if (block.rect as Rect2).get_center().distance_to(c) > reach:
				continue
			for p: Dictionary in bs.call("plan_poles", plan, ix, iz):
				var kind: String = names[int(p.kind)]
				found[kind] = int(found.get(kind, 0)) + 1
				if want != "" and kind != want:
					continue
				var at: Vector2 = p.at
				var inward: Vector2 = p.out
				var along: Vector2 = p.along
				var eye := at - inward * 5.6 + along * 18.0
				var look := (at + inward * 1.5 + Vector2(0, 0)) - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var eye2 := at - inward * 6.5 + along * 6.0
				var look2 := (at + inward * 1.5) - eye2
				var yaw2 := rad_to_deg(atan2(-look2.x, -look2.y))
				print("POLE %s block=%d,%d e=%d a=%d at=%.1f,%.1f EYE=%.1f,1.7,%.1f,%.0f,12 CLOSE=%.1f,1.7,%.1f,%.0f,30" % [
					kind, ix, iz, int(p.e), int(p.a), at.x, at.y, eye.x, eye.y, yaw, eye2.x, eye2.y, yaw2])
	print("FOUND ", found)
	quit()
