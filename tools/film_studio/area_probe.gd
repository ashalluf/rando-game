extends Node
## Scans candidate ground for the film studio lot: district, zone, height, and what else is
## there (freeway, light rail, river, sites, landmarks, schools). Headless, a minute.
##   godot --headless --path . res://tools/film_studio/area_probe.tscn
func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 8:
		await get_tree().process_frame
	var plan = city.get("plan")
	var m = plan.macro
	var dn := ["DT", "MID", "SUB", "IND", "CAM", "BCH"]
	for z in range(-1100, 700, 100):
		var row := "%5d " % z
		for x in range(-600, 2000, 100):
			var p := Vector2(x, z)
			var c := "."
			if m.zone_at(p) != MacroMap.Zone.CITY:
				c = "~"
			else:
				var d: int = m.district_at(p)
				c = ["D", "m", "s", "i", "c", "b"][d]
				var idx: Vector2i = plan.block_index_at(p)
				var b: Dictionary = plan.block(idx.x, idx.y)
				if b.has("site"):
					c = "S"
				elif b.has("grounds"):
					c = "G"
				elif m.freeway and m.freeway.blocks_rect(b.rect, 3.0):
					c = "F"
				elif m.river and plan.river_block(idx.x, idx.y):
					c = "R"
				elif not Landmarks.in_rect(b.rect.grow(30)).is_empty():
					c = "L"
			row += c
		print(row)
	print("x from -600 step 100")
	for iz in range(-12, 4):
		for ix in range(-6, 14):
			var b: Dictionary = plan.block(ix, iz)
			var r: Rect2 = b.rect
			if r.position.x < -300 or r.position.x > 1500 or r.position.y < -950 or r.position.y > 200:
				continue
			print("B %d,%d rect=(%.0f,%.0f %.0fx%.0f) d=%d k=%d site=%s gr=%s fw=%s rx=%.1f/%.1f rz=%.1f/%.1f" % [ix, iz, r.position.x, r.position.y, r.size.x, r.size.y, b.district, b.kind, b.get("site", ""), b.get("grounds", ""), m.freeway.blocks_rect(r, 3.0), plan.road_pos(0, ix), plan.road_width(0, ix), plan.road_pos(1, iz), plan.road_width(1, iz)])
	get_tree().quit()
