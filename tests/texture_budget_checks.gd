extends RefCounted
## The texture budget checks for tests/smoke_test.gd (docs/HANDOFF.md, "Texture budget"): every
## texture the game ships is imported the project's way (VRAM compressed, mipmapped, detect_3d off,
## normal maps flagged by name), each one held to its size by tools/texture_budget/budget.txt
## (the very rules tools/fix_texture_imports.py writes), no picture is shipped twice under two
## names (Godot loads each copy as its own texture), and the budgeted textures really load at
## their limit. Reads the .import files and the sources, so it runs headless.

const BUDGET := "res://tools/texture_budget/budget.txt"
const NORMAL_HINTS := ["_nor_gl", "_nor_dx", "_normalgl", "_normal", "_nrm"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"]
## Imported for something other than the 3D world (and never loaded by the game): kept as they are.
const EXEMPT := ["res://assets/models/thumbs/", "res://assets/models/pedestrian_a_mask.png",
	"res://assets/models/pedestrian_c_mask.png"]

var _t: Object


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Object) -> void:
	_t = t
	var rules := _budget()
	_check(rules.size() >= 4, "the texture budget has its rules (%d)" % rules.size())
	var files: Array[String] = []
	_walk("res://assets", files)
	var bad_mode: Array[String] = []
	var bad_normal: Array[String] = []
	var bad_limit: Array[String] = []
	var md5s := {}
	var dupes: Array[String] = []
	var textures := 0
	for src in files:
		var imp := src + ".import"
		if not FileAccess.file_exists(imp):
			continue
		var text := FileAccess.get_file_as_string(imp)
		if not text.contains("importer=\"texture\""):
			continue
		var exempt := false
		for e in EXEMPT:
			if src.begins_with(e):
				exempt = true
		if exempt:
			continue
		textures += 1
		var p := _params(text)
		if p.get("compress/mode") != "2" or p.get("mipmaps/generate") != "true" \
				or p.get("detect_3d/compress_to") != "0":
			bad_mode.append(src)
		var base := src.get_file().to_lower()
		var is_normal := false
		for h in NORMAL_HINTS:
			if base.contains(h):
				is_normal = true
		if is_normal != (p.get("compress/normal_map") == "1"):
			if not (not is_normal and p.get("compress/normal_map") == "2"):
				bad_normal.append(src)
		var want := 0
		for r in rules:
			if (r[0] as RegEx).search(src) != null:
				want = r[1]
				break
		if int(p.get("process/size_limit", "0")) != want:
			bad_limit.append("%s (%s, budget %d)" % [src, p.get("process/size_limit", "0"), want])
		var h := FileAccess.get_md5(src)
		if md5s.has(h):
			dupes.append("%s = %s" % [src, md5s[h]])
		else:
			md5s[h] = src
	_check(textures > 400, "the texture census sees the game's textures (%d)" % textures)
	_check(bad_mode.is_empty(), "every texture is VRAM compressed with mipmaps and detect_3d off %s" % [bad_mode.slice(0, 4)])
	_check(bad_normal.is_empty(), "every normal map is flagged as one, and nothing else is %s" % [bad_normal.slice(0, 4)])
	_check(bad_limit.is_empty(), "every texture's size limit is the budget's (run tools/fix_texture_imports.py) %s" % [bad_limit.slice(0, 4)])
	_check(dupes.is_empty(), "no picture ships twice under two names (tools/texture_budget/dedupe_glb_images.py) %s" % [dupes.slice(0, 4)])
	# The budget is what really loads (the dummy renderer still reads the .ctex header).
	var body := load("res://assets/models/crowd_a_body.jpg") as Texture2D
	_check(body != null and body.get_width() <= 1024, "a crowd body atlas loads at its budget (%d)" % (body.get_width() if body else -1))
	var pigeon := load("res://assets/textures/birds/pigeon_albedo.png") as Texture2D
	_check(pigeon != null and pigeon.get_width() <= 512, "a bird atlas loads at its budget (%d)" % (pigeon.get_width() if pigeon else -1))
	# tree_b and the jacaranda draw with tree_a's own leaf and bark maps, not copies.
	var shared := _texture_paths("res://assets/models/tree_b.glb")
	_check(shared.has("res://assets/models/tree_a_leaves_diff.jpg") and shared.has("res://assets/models/tree_a_branches_nor_gl.jpg"),
		"tree_b shares tree_a's leaf and bark maps")


func _budget() -> Array:
	var rules := []
	var f := FileAccess.open(BUDGET, FileAccess.READ)
	if f == null:
		return rules
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var cut := line.rfind(" ")
		var re := RegEx.new()
		if re.compile(line.substr(0, cut).strip_edges()) == OK:
			rules.append([re, int(line.substr(cut + 1))])
	return rules


func _params(text: String) -> Dictionary:
	var out := {}
	var inside := false
	for line in text.split("\n"):
		if line.begins_with("["):
			inside = line == "[params]"
			continue
		var eq := line.find("=")
		if inside and eq > 0:
			out[line.substr(0, eq)] = line.substr(eq + 1)
	return out


func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() in IMAGE_EXT:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)


func _texture_paths(glb: String) -> Dictionary:
	var out := {}
	var scene := load(glb) as PackedScene
	if scene == null:
		return out
	var root := scene.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			for prop in ["albedo_texture", "normal_texture", "roughness_texture", "ao_texture"]:
				var tex = m.get(prop)
				if tex is Texture2D:
					out[(tex as Texture2D).resource_path] = true
	root.free()
	return out
