extends SceneTree
func _initialize() -> void:
	await process_frame
	var m := MacroMap.new()
	m.seed = 1337
	m.setup()
	var r := Rect2(1800, 6300, 1000, 600)
	for s in m.hill_roads.segments_in(r):
		print("SEG %s -> %s w %.1f h %.1f..%.1f %s" % [s.a, s.b, s.width, s.get("ha", 0.0), s.get("hb", 0.0), s.get("name", "")])
	for e in m.hill_roads.mansions_in(r):
		print("EST ", e.pos, " ", e.get("h", 0.0))
	print("ZONE ", MacroMap.zone_name(m.zone_at(Vector2(2170, 6655))))
	quit()
