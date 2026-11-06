extends SceneTree
## Prints the terminal's moving machines for framing stills (PortLife): every working crane's base,
## bay, slots, period and the clock times of its steps (lift off the chassis, over the ship, the
## drops), the tractors' loop, the straddle loops and the gate chunk. Headless, seconds:
##   godot --headless --path . --script tools/port_life_probe.gd [-- T=<clock>]
## (Nothing here is named as a type: they compile before the autoloads exist.)
## T prints each crane's pose at that clock (PORT_T on still_shot.gd).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var pl: GDScript = load("res://scripts/world/port_life.gd")
	var t := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("T="):
			t = a.trim_prefix("T=").to_float()
	var g: Dictionary = pl.grid(plan)
	print("GRID xs=", g.xs, " zs=", g.zs, " gate=", g.gate, " gate_rect=", plan.owned_rect(g.gate.x, g.gate.y))
	var ship: Vector2 = pl.ship_anchor()
	var macro = plan.macro
	var a: Vector2i = plan.block_index_at(macro.port_rect.position + Vector2(1, 1))
	var b: Vector2i = plan.block_index_at(macro.port_rect.end - Vector2(1, 1))
	for ix in range(a.x, b.x + 1):
		var area: Rect2 = plan.owned_rect(ix, b.y)
		var qz := area.end.y
		var crane_z := qz - 3.0 - 30.48 * 0.5
		for k in 2:
			var x := area.position.x + area.size.x * (0.25 + 0.5 * k)
			if absf(x - ship.x) >= 95.0:
				continue
			var bx: float = pl.bay_x(x)
			var c: Dictionary = pl.crane_plan(plan, Vector3(bx, 0.2, crane_z), ix * 2 + k)
			print("CRANE %d base=(%.1f, %.1f) lane_z=%.1f P=%s Q=%s period=%.1f phase=%.1f loop=%.0f m" % [ix * 2 + k, bx, crane_z, c.lane_z, str(c.P.centre), str(c.Q.centre), c.period, c.phase, c.loop.length])
			var line := "  even steps:"
			for st: Dictionary in c.halves[0]:
				line += " %.0f" % float(st.t1)
			print(line)
			if t >= 0.0:
				var p: Dictionary = pl.crane_pose(c, t)
				print("  at T=%.1f: step %d trolley_z=%.1f spreader_y=%.1f box_on_spreader=%s tractors s=%.1f, %.1f" % [t, p.step, p.trolley_z, p.spreader_y, str((p.spreader_box as Array).size() > 0), p.tractors[0].s, p.tractors[1].s])
	var loops: Array = pl.straddle_loops(plan)
	for lp: Dictionary in loops:
		print("STRADDLE loop %.0f m, %d cars, first corner %s" % [lp.path.length, (lp.cars as Array).size(), str((lp.path.pts as PackedVector2Array)[0])])
		if t >= 0.0:
			for car: Dictionary in lp.cars:
				var at: Array = pl.path_at(lp.path, t * 5.6 + float(car.offset))
				print("  straddle %s at T=%.1f: %s heading %s loaded=%s" % [car.id, t, str(at[0]), str(at[1]), str((car.look as Array).size() > 0)])
	quit()
