extends RefCounted
## The static caches a run is left holding (docs/HANDOFF.md, the perf-audit-2 section): every
## `static var` under res://scripts holding a container or a resource, sized by memory_probe.gd's
## Sizer, biggest first. The smoke test calls it at its very end with MEMORY_CENSUS=1, after the
## city is freed, so what is listed is what the caches alone keep alive after ~2,400 checks.

static func census(top: int = 40) -> void:
	var probe: GDScript = load("res://tools/memory_probe.gd")
	var sizer_class = probe.Sizer
	var rows: Array = []
	for path in probe._scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		var names: Array = []
		for line in src.split("\n"):
			if line.begins_with("static var "):
				var n := line.trim_prefix("static var ").strip_edges()
				var end := 0
				while end < n.length() and (n[end] == "_" or n[end].is_valid_identifier() or n[end].is_valid_int()):
					end += 1
				names.append(n.substr(0, end))
		if names.is_empty():
			continue
		var script: Script = load(path)
		if script == null:
			continue
		for n in names:
			var v: Variant = script.get(n)
			var t := typeof(v)
			if t != TYPE_DICTIONARY and t != TYPE_ARRAY and t != TYPE_OBJECT and t < TYPE_PACKED_BYTE_ARRAY:
				continue
			var s = sizer_class.new()
			s.size(v)
			if s.bytes < 65536:
				continue
			rows.append([s.bytes, "%s.%s" % [path.get_file().get_basename(), n], s.entries, s.meshes])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0
	for r in rows:
		total += r[0]
	printerr("CENSUS %d caches over 64 kB, %.1f MB in all (allocator %d MB)" % [rows.size(), total / 1048576.0,
		int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576])
	for i in mini(top, rows.size()):
		var r: Array = rows[i]
		printerr("CENSUS %8.2f MB  %-48s entries %7d  meshes %5d" % [r[0] / 1048576.0, r[1], r[2], r[3]])
