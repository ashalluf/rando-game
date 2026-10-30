extends SceneTree
## Lists imported assets nothing reaches: neither named in scripts / scenes / resources / shaders
## (by file name or stem, which catches "res://assets/models/%s.glb" tables) nor a dependency of
## something that is. Candidates for the Web preset's exclude_filter; verify each by hand.
## godot --headless --path . --script tools/webshot/unused_probe.gd


var _text := ""


func _initialize() -> void:
	for p in _files("res://", [".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".godot", ".cfg"]):
		if p.begins_with("res://tools/") or p.begins_with("res://tests/") or p.begins_with("res://build/"):
			continue
		_text += FileAccess.get_file_as_string(p) + "\n"
	var assets := _files("res://assets", [".glb", ".jpg", ".png", ".ogg", ".wav", ".mp3", ".res", ".tres", ".exr", ".hdr", ".webp"])
	var reached := {}
	var queue: Array[String] = []
	for a in assets:
		var stem := a.get_file().get_basename()
		if _text.contains(a.get_file()) or _text.contains(stem):
			reached[a] = true
			queue.append(a)
	while not queue.is_empty():
		var p: String = queue.pop_back()
		for d in ResourceLoader.get_dependencies(p):
			var path := d.get_slice("::", 2) if d.contains("::") else d
			if path.begins_with("uid://"):
				path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
			if not reached.has(path):
				reached[path] = true
				queue.append(path)
	var out: Array[String] = []
	for a in assets:
		if not reached.has(a):
			out.append(a)
	for a in out:
		print("UNUSED ", a)
	print("UNUSED_COUNT ", out.size(), " of ", assets.size())
	quit()


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		for e in exts:
			if f.ends_with(e):
				out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out.append_array(_files(dir.path_join(d), exts))
	return out
