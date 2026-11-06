extends SceneTree
## Lists every drawn node with a visibility range, grouped by kind, and flags the HARD cuts: a
## range with no fade (VISIBILITY_RANGE_FADE_DISABLED or a zero margin) is a pop the eye catches
## while driving or flying. Headless is enough (the tree is the same; only the GPU is missing).
##
##   godot --headless --path . --script tools/lod_pops/range_audit.gd -- --spawn=2363,960,0,-8,2 --nohud
##
## Env: FRAMES (default 400, streaming), ALL=1 also prints the faded kinds.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 400
	for i in frames:
		await process_frame
	var kinds := {}
	_walk(root, kinds)
	var rows: Array = []
	for k: String in kinds:
		rows.append(kinds[k])
	rows.sort_custom(func(a, b): return a.n > b.n)
	var show_all := OS.get_environment("ALL") == "1"
	for r: Dictionary in rows:
		if not r.hard and not show_all:
			continue
		print("RANGE %s %-44s n=%d begin=%.0f end=%.0f bm=%.1f em=%.1f fade=%d shadow=%d" % [
			"HARD" if r.hard else "fade", r.key, r.n, r.begin, r.end, r.bm, r.em, r.fade, r.shadow])
	quit()


func _kind(n: Node) -> String:
	var nm := String(n.name)
	var re := RegEx.create_from_string("[@0-9_-]+$")
	nm = re.sub(nm, "", true)
	var re2 := RegEx.create_from_string("@.*$")
	nm = re2.sub(nm, "", true)
	var p := n.get_parent()
	var pn := ""
	if p:
		var s: Script = p.get_script()
		pn = s.resource_path.get_file().get_basename() if s else re.sub(String(p.name), "", true)
	return "%s/%s" % [pn, nm]


func _walk(n: Node, kinds: Dictionary) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
			var hard := g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if g.visibility_range_end > 0.0 and g.visibility_range_end_margin <= 0.0:
				hard = true
			if g.visibility_range_begin > 0.0 and g.visibility_range_begin_margin <= 0.0:
				hard = true
			var key := _kind(n) + (" [H]" if hard else "")
			if not kinds.has(key):
				kinds[key] = {"key": key, "n": 0, "hard": hard, "begin": g.visibility_range_begin,
					"end": g.visibility_range_end, "bm": g.visibility_range_begin_margin,
					"em": g.visibility_range_end_margin, "fade": g.visibility_range_fade_mode,
					"shadow": g.cast_shadow}
			kinds[key].n += 1
	for c in n.get_children():
		_walk(c, kinds)
