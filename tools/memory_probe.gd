extends SceneTree
## Where the city's memory goes. Loads the city, settles, drives the player DRIVE metres (default
## 2000) along +X at SPEED m/s (default 45, a car's top speed), settles again, and prints:
##   RSS lines        peak and current resident memory (/proc/self/status) and Godot's own
##                    allocator (Performance MEMORY_STATIC) at each stage;
##   CACHE lines      every `static var` of every script under res://scripts that holds a
##                    container or a resource, sized: entries, meshes (vertex + index bytes of
##                    their surfaces and LODs), packed arrays, images; biggest first;
##   TREE lines       what the scene holds, per top-level owner (each streamed chunk counted as
##                    FULL or LOD, the far city, the rest): mesh bytes (each mesh once), MultiMesh
##                    buffers, collision shapes' faces.
##
##   godot --headless --path . --script tools/memory_probe.gd
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/memory_probe.gd
##
## Knobs (environment): DRIVE, SPEED, SETTLE (frames, default 300), TOP (cache rows, 40),
## CACHES=0 skips the cache census (it loads every script). Sizes are estimates of the CPU-side
## arrays; RSS is the truth. Under --headless the dummy renderer keeps every mesh's arrays on the
## CPU too, so a mesh held in a cache and drawn costs its bytes twice there.

var _peak_rss := 0
var _last_rows: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settle := int(_env("SETTLE", "300"))
	var drive := float(_env("DRIVE", "2000"))
	var speed := float(_env("SPEED", "45"))
	_rss("start")
	var t0 := Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var city: Node = scene.instantiate()
	root.add_child(city)
	for i in 3:
		await _frame()
	print("LOAD %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_rss("city loaded")
	for i in settle:
		await _frame()
	_rss("settled")
	if _env("CACHES", "1") != "0":
		_caches("settled")
	_tree(city, "settled")
	var player := get_first_node_in_group("player") as Node3D
	if player != null and drive > 0.0:
		var ws: Node = root.get_node("/root/WorldState")
		var start: Vector3 = ws.call("to_world", player.global_position)
		var gone := 0.0
		var step := speed / 60.0
		var next_report := 500.0
		while gone < drive:
			gone += step
			var w := start + Vector3(gone, 0.0, 0.0)
			var local: Vector3 = ws.call("to_local", w)
			local.y = float(city.call("ground_height_at", local)) + 3.0
			player.global_position = local
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
			await _frame()
			if gone >= next_report:
				_rss("drove %d m" % int(next_report))
				next_report += 500.0
		for i in settle:
			await _frame()
		_rss("after drive, settled")
		if _env("CACHES", "1") != "0":
			_caches("after drive")
		_tree(city, "after drive")
	print("RSS PEAK %d MB" % (_peak_rss / 1048576))
	if _env("EXCLUSIVE", "0") != "0":
		await _exclusive()
	quit(0)


## Destructive, last: empties each big cache in turn and prints what Godot's allocator gets back
## (what the cache alone keeps alive; anything the scene still uses stays).
func _exclusive() -> void:
	for row in _last_rows.slice(0, int(_env("TOP", "40"))):
		var v: Variant = row[4]
		var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		if typeof(v) == TYPE_DICTIONARY:
			(v as Dictionary).clear()
		elif typeof(v) == TYPE_ARRAY:
			(v as Array).clear()
		else:
			continue
		for i in 3:
			await _frame()
		var after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		print("EXCL  %8.2f MB  %s" % [(before - after) / 1048576.0, row[1]])


func _frame() -> void:
	await process_frame
	var r := _read_status()
	_peak_rss = maxi(_peak_rss, r.x)


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v


## (VmRSS, VmHWM) in bytes.
static func _read_status() -> Vector2i:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var rss := 0
	var hwm := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			rss = int(line.split(":")[1].strip_edges().split(" ")[0]) * 1024
		elif line.begins_with("VmHWM:"):
			hwm = int(line.split(":")[1].strip_edges().split(" ")[0]) * 1024
	return Vector2i(rss, hwm)


func _rss(label: String) -> void:
	var r := _read_status()
	_peak_rss = maxi(_peak_rss, r.x)
	print("RSS %-22s rss %6d MB  hwm %6d MB  godot %6d MB  objects %d  resources %d  nodes %d" % [
		label, r.x / 1048576, r.y / 1048576,
		int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


# --- sizing ---------------------------------------------------------------------------------

class Sizer:
	## Bytes of one vertex of a surface with this format (the CPU arrays' layout, roughly).
	static func _stride(fmt: int) -> int:
		var s := 12
		if fmt & Mesh.ARRAY_FORMAT_NORMAL:
			s += 12
		if fmt & Mesh.ARRAY_FORMAT_TANGENT:
			s += 16
		if fmt & Mesh.ARRAY_FORMAT_COLOR:
			s += 16
		if fmt & Mesh.ARRAY_FORMAT_TEX_UV:
			s += 8
		if fmt & Mesh.ARRAY_FORMAT_TEX_UV2:
			s += 8
		for c in 4:
			if fmt & (Mesh.ARRAY_FORMAT_CUSTOM0 << c):
				s += 16
		if fmt & Mesh.ARRAY_FORMAT_BONES:
			s += 16
		if fmt & Mesh.ARRAY_FORMAT_WEIGHTS:
			s += 16
		return s


	static func mesh_bytes(m: Mesh) -> int:
		if m == null:
			return 0
		var b := 0
		for i in m.get_surface_count():
			var am := m as ArrayMesh
			if am == null:
				# A PrimitiveMesh: its arrays are small and rebuilt on demand.
				b += 1024
				continue
			b += am.surface_get_array_len(i) * _stride(am.surface_get_format(i))
			b += am.surface_get_array_index_len(i) * 4
		return b

	var seen := {}
	var bytes := 0
	var meshes := 0
	var entries := 0

	func size(v: Variant, depth: int = 0) -> void:
		if depth > 6:
			return
		match typeof(v):
			TYPE_DICTIONARY:
				var d: Dictionary = v
				entries += d.size()
				bytes += d.size() * 48
				for k in d:
					size(k, depth + 1)
					size(d[k], depth + 1)
			TYPE_ARRAY:
				var a: Array = v
				entries += a.size()
				bytes += a.size() * 24
				for e in a:
					size(e, depth + 1)
			TYPE_PACKED_BYTE_ARRAY:
				bytes += (v as PackedByteArray).size()
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
				bytes += v.size() * 4
			TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
				bytes += v.size() * 8
			TYPE_PACKED_VECTOR3_ARRAY:
				bytes += v.size() * 12
			TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
				bytes += v.size() * 16
			TYPE_STRING:
				bytes += (v as String).length() * 4
			TYPE_OBJECT:
				if not is_instance_valid(v):
					return
				var o: Object = v
				var id := o.get_instance_id()
				if seen.has(id):
					return
				seen[id] = true
				if o is Mesh:
					meshes += 1
					bytes += Sizer.mesh_bytes(o as Mesh)
				elif o is Image:
					bytes += (o as Image).get_data_size()
				elif o is MultiMesh:
					var mm := o as MultiMesh
					bytes += mm.instance_count * 64
					size(mm.mesh, depth + 1)
				elif o is ConcavePolygonShape3D:
					bytes += (o as ConcavePolygonShape3D).get_faces().size() * 12
				elif o is ImageTexture:
					var t := o as ImageTexture
					bytes += t.get_width() * t.get_height() * 4
				elif o is TriangleMesh:
					bytes += 0
				else:
					bytes += 256


func _caches(label: String) -> void:
	var rows: Array = []
	for path in _scripts("res://scripts"):
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
			var s := Sizer.new()
			s.size(v)
			if s.bytes < 16384:
				continue
			rows.append([s.bytes, "%s.%s" % [path.get_file().get_basename(), n], s.entries, s.meshes, v])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	_last_rows = rows
	var total := 0
	for r in rows:
		total += r[0]
	print("CACHE %s: %d rows over 16 kB, %.1f MB in all" % [label, rows.size(), total / 1048576.0])
	var top := int(_env("TOP", "40"))
	for i in mini(top, rows.size()):
		var r: Array = rows[i]
		print("CACHE   %8.2f MB  %-48s entries %7d  meshes %5d" % [r[0] / 1048576.0, r[1], r[2], r[3]])
		if r[0] > 4 * 1048576 and typeof(r[4]) == TYPE_DICTIONARY:
			_cache_keys(r[4])


## The biggest key families of one cache (keys cut at their first digit or separator).
func _cache_keys(d: Dictionary) -> void:
	var fam := {}
	for k in d:
		var name := str(k) if typeof(k) == TYPE_STRING or typeof(k) == TYPE_STRING_NAME else type_string(typeof(k))
		if typeof(k) == TYPE_OBJECT and is_instance_valid(k):
			name = (k as Object).get_class() + ":" + ((k as Resource).resource_path.get_file() if k is Resource else "")
		var cut := name.length()
		for i in name.length():
			if name[i].is_valid_int() or name[i] in ":|,(/":
				cut = i
				break
		var f := name.substr(0, maxi(cut, 1))
		var s := Sizer.new()
		var val: Variant = d[k]
		s.size(val)
		var a: Array = fam.get(f, [0, 0, 0])
		a[0] += s.bytes
		a[1] += 1
		# Held by the cache alone: the dictionary and `val` here are its only references.
		if typeof(val) == TYPE_OBJECT and is_instance_valid(val) and val is RefCounted \
				and (val as RefCounted).get_reference_count() <= 2:
			a[2] += s.bytes
		fam[f] = a
	var rows: Array = []
	for f in fam:
		rows.append([fam[f][0], f, fam[f][1], fam[f][2]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("CACHE             %7.2f MB  %-36s x%-5d cache-only %7.2f MB" % [r[0] / 1048576.0, r[1], r[2], r[3] / 1048576.0])


static func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out


func _tree(city: Node, label: String) -> void:
	var groups := {}
	var seen := {}
	for top in city.get_children():
		var key := str(top.name)
		if top.has_method("retire") and top.get("level") != null:
			key = "chunk " + ("FULL" if int(top.get("level")) == 0 else "LOD")
		elif top.get_script() != null:
			key = (top.get_script() as Script).resource_path.get_file().get_basename()
		var acc: Array = groups.get(key, [0, 0, 0, 0])
		_walk(top, acc, seen)
		groups[key] = acc
	var rows: Array = []
	for k in groups:
		rows.append([k, groups[k]])
	rows.sort_custom(func(a, b): return a[1][0] + a[1][1] + a[1][2] > b[1][0] + b[1][1] + b[1][2])
	_dups(city)
	print("TREE %s (mesh bytes each mesh once, multimesh buffers, collision faces, nodes)" % label)
	for r in rows.slice(0, 30):
		var a: Array = r[1]
		print("TREE   %-34s meshes %7.1f MB  mm %6.1f MB  shapes %6.1f MB  nodes %6d" % [r[0], a[0] / 1048576.0, a[1] / 1048576.0, a[2] / 1048576.0, a[3]])


func _walk(n: Node, acc: Array, seen: Dictionary) -> void:
	acc[3] += 1
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		if m and not seen.has(m.get_instance_id()):
			seen[m.get_instance_id()] = true
			acc[0] += Sizer.mesh_bytes(m)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and not seen.has(mm.get_instance_id()):
			seen[mm.get_instance_id()] = true
			var per := 48
			if mm.use_colors:
				per += 16
			if mm.use_custom_data:
				per += 16
			acc[1] += mm.instance_count * per
			if mm.mesh and not seen.has(mm.mesh.get_instance_id()):
				seen[mm.mesh.get_instance_id()] = true
				acc[0] += Sizer.mesh_bytes(mm.mesh)
	elif n is CollisionShape3D:
		var s := (n as CollisionShape3D).shape
		if s and not seen.has(s.get_instance_id()):
			seen[s.get_instance_id()] = true
			if s is ConcavePolygonShape3D:
				acc[2] += (s as ConcavePolygonShape3D).get_faces().size() * 12
			elif s is ConvexPolygonShape3D:
				acc[2] += (s as ConvexPolygonShape3D).points.size() * 12
			elif s is HeightMapShape3D:
				acc[2] += (s as HeightMapShape3D).map_data.size() * 4
	for c in n.get_children():
		_walk(c, acc, seen)


## Meshes in the scene that are separate objects with the same content (name, surfaces, vertex
## and index counts, bounds): what sharing them would save.
func _dups(city: Node) -> void:
	var sig := {}
	for n in city.find_children("*", "", true, false):
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			m = (n as MultiMeshInstance3D).multimesh.mesh
		if m == null or not (m is ArrayMesh):
			continue
		var am := m as ArrayMesh
		var k := "%s|%d|%d|%d|%s" % [am.resource_name, am.get_surface_count(),
			am.surface_get_array_len(0) if am.get_surface_count() > 0 else 0,
			am.surface_get_array_index_len(0) if am.get_surface_count() > 0 else 0, am.get_aabb()]
		var g: Dictionary = sig.get(k, {})
		g[am.get_instance_id()] = am
		sig[k] = g
	var rows: Array = []
	var total := 0
	for k in sig:
		var g: Dictionary = sig[k]
		if g.size() < 2:
			continue
		var b := Sizer.mesh_bytes(g.values()[0])
		rows.append([b * (g.size() - 1), k, g.size()])
		total += b * (g.size() - 1)
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("DUP %d mesh contents drawn as more than one object, %.1f MB in the extra copies" % [rows.size(), total / 1048576.0])
	for r in rows.slice(0, 15):
		print("DUP   %7.2f MB  x%-4d %s" % [r[0] / 1048576.0, r[2], str(r[1]).left(110)])
