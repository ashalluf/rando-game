extends SceneTree
## Prints the blocks round AT=x,z (index, kind, district, rect and the roads either side): to frame
## gi_shot.gd's EYEs.   godot --headless --path . --script tools/gi_review/where.gd -- AT=480,480


func _initialize() -> void:
	var at := Vector2(0, 0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("AT="):
			var v := a.trim_prefix("AT=").split(",")
			at = Vector2(v[0].to_float(), v[1].to_float())
	var plan := GroundCoverage.make_plan(1337)
	var c: Vector2i = plan.block_index_at(at)
	if "FW=1" in OS.get_cmdline_user_args() and plan.macro.freeway:
		for sg in plan.macro.freeway.segments_in(Rect2(at - Vector2(60, 60), Vector2(120, 120))):
			var mid: Vector2 = (Vector2(sg.a.x, sg.a.z) + Vector2(sg.b.x, sg.b.z)) * 0.5 if sg.a is Vector3 else (sg.a + sg.b) * 0.5
			print("SEG mid %s block %s keys %s" % [mid, plan.block_index_at(mid), sg.keys()])
	if "FIND=1" in OS.get_cmdline_user_args():
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				var bb: Dictionary = plan.block(c.x + dx, c.y + dz)
				if int(bb.get("kind", 0)) == CityPlan.BlockKind.PARK and str(bb.get("grounds", "")) == "" and str(bb.get("site", "")) == "":
					print("PARK %d,%d owned %s" % [c.x + dx, c.y + dz, plan.owned_rect(c.x + dx, c.y + dz)])
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := c.x + dx
			var iz := c.y + dz
			var b: Dictionary = plan.block(ix, iz)
			print("block %d,%d kind %s grounds %s site %s district %d owned %s road_x %.1f w %.1f road_z %.1f w %.1f" % [ix, iz,
				b.get("kind", "?"), b.get("grounds", ""), b.get("site", ""), plan.district_at(at), plan.owned_rect(ix, iz),
				plan.road_pos(0, ix), plan.road_width(0, ix), plan.road_pos(1, iz), plan.road_width(1, iz)])
	quit()
