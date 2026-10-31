extends SceneTree
## Finds forecourt ground laid twice: builds the FULL chunks round a point and lists every pair
## of LotFill ground rects (CityChunk._fill_ground) from DIFFERENT kinds or chunks that overlap.
## Coplanar pavings z-fight into fine screen-space stripes at eye level, which reads as aliasing.
##   godot --headless --path . --script tools/paving_aa/overlap_probe.gd -- --spawn=x,z,0,0
## R=blocks round it (default 2).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var reach := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 2
	var start: Vector2i = plan.block_index_at(c)
	var all: Array = []  # [chunk key, kind, Rect2 in world]
	for ix in range(start.x - reach, start.x + reach + 1):
		for iz in range(start.y - reach, start.y + reach + 1):
			var chunk = city.call("_new_chunk", Vector2i(ix, iz), 0)
			# Stepped by hand: LotFill.commit() clears _fill_ground in the finish step, so keep
			# the last copy taken before it.
			chunk.call("begin_build")
			var fg: Dictionary = {}
			var guard := 0
			while guard < 5000:
				guard += 1
				var done: bool = chunk.call("build_step")
				var cur: Dictionary = chunk.get("_fill_ground")
				if not cur.is_empty():
					fg = cur.duplicate(true)
				if done:
					break
			var off: Vector3 = Vector3.ZERO
			var n := 0
			for kind: String in fg:
				for r: Rect2 in fg[kind]:
					all.append(["%d,%d" % [ix, iz], kind, Rect2(r.position + Vector2(off.x, off.z), r.size)])
					if kind.begins_with("paving") and r.get_area() > 60.0:
						print("  RECT %s %s centre=%.1f,%.1f size=%.1fx%.1f" % [str(Vector2i(ix, iz)), kind, r.get_center().x, r.get_center().y, r.size.x, r.size.y])
					n += 1
			print("BLOCK %d,%d district=%d fill=%d kinds=%s pos=%s" % [ix, iz, int(plan.block(ix, iz).district), n, str(fg.keys()), str(chunk.global_position)])
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	var hits := 0
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Array = all[i]
			var b: Array = all[j]
			if a[0] == b[0] and a[1] == b[1]:
				continue
			var lift_a := String(a[1]).begins_with("paving")
			var lift_b := String(b[1]).begins_with("paving")
			if lift_a != lift_b:
				continue
			var x: Rect2 = (a[2] as Rect2).intersection(b[2])
			if x.size.x > 0.05 and x.size.y > 0.05:
				hits += 1
				var m := x.get_center()
				print("OVERLAP %s %s / %s %s area=%.1f at=%.1f,%.1f EYE=%.1f,1.7,%.1f,180,-15" % [a[0], a[1], b[0], b[1], x.get_area(), m.x, m.y, m.x, m.y - 6.0])
	print("PAIRS ", all.size(), " OVERLAPS ", hits)
	quit()
