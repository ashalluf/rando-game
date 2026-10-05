class_name LoadCache
extends RefCounted
## A disk cache for what every launch computes the same way from the same code and seed (docs/
## HANDOFF.md, "Load time"). Today: the basin bake (MacroMap.bake(), ~18 s of GDScript on the build
## box, the biggest single stage of a launch), stored in user://load_cache/.
##
## SAFE BY CONSTRUCTION: an entry's key is the md5 of everything the result can depend on -
##   * a FINGERPRINT of the code: the md5 of every file under res://scripts (the .gd text in the
##     editor, the .gdc tokens in an export) - any edit to any script misses the cache;
##   * the value of every environment variable any script reads (the A/B switches: RIVER=0,
##     MARINA=0, ...; their names are read out of the scripts, so a new switch is covered with no
##     list to keep) and the command line's user arguments (--no-replica, --no-river, ...);
##   * the engine version, the platform (the web bakes smaller), and the caller's own inputs.
## A miss is only a slower launch; a hit is the very bytes the bake wrote. `LOAD_CACHE=0` in the
## environment (or `-- --no-load-cache`) never reads or writes it (the A/B). Web builds skip it.

const DIR := "user://load_cache"
## Entries of one kind kept on disk (the newest); older ones are deleted on write.
const KEEP := 2

static var _fingerprint: String = ""


## False when the cache is off (LOAD_CACHE=0, --no-load-cache, the web).
static func enabled() -> bool:
	return OS.get_environment("LOAD_CACHE") != "0" and not OS.has_feature("web") \
			and not OS.get_cmdline_user_args().has("--no-load-cache")


## The md5 of the code, the switches and the platform (computed once a run).
static func fingerprint() -> String:
	if _fingerprint != "":
		return _fingerprint
	var t0 := Time.get_ticks_usec()
	var files := PackedStringArray()
	_list("res://scripts", files)
	files.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var env_names := {}
	var re := RegEx.create_from_string("get_environment\\(\"([A-Za-z0-9_]+)\"\\)")
	for f in files:
		var bytes := FileAccess.get_file_as_bytes(f)
		ctx.update(f.to_utf8_buffer())
		ctx.update(bytes)
		if f.ends_with(".gd"):
			for m in re.search_all(bytes.get_string_from_utf8()):
				env_names[m.get_string(1)] = true
	# What the code reads besides itself (models, textures, scenes): each file's path and size -
	# the bake reads none of them, but anything cached later may. Sizes, not contents: hundreds of
	# megabytes are not read at every launch; an exported build's own .pck stands in for them too.
	var assets := PackedStringArray()
	_list("res://assets", assets)
	_list("res://scenes", assets)
	assets.sort()
	for f in assets:
		var fa := FileAccess.open(f, FileAccess.READ)
		ctx.update(("%s:%d" % [f, fa.get_length() if fa else -1]).to_utf8_buffer())
	if not OS.has_feature("editor"):
		var exe := OS.get_executable_path()
		var pck := exe.get_basename() + ".pck"
		for x in [exe, pck, exe.get_base_dir().path_join("../Resources/" + pck.get_file())]:
			if FileAccess.file_exists(x):
				var fx := FileAccess.open(x, FileAccess.READ)
				ctx.update(("%s:%d:%d" % [x, FileAccess.get_modified_time(x), fx.get_length() if fx else -1]).to_utf8_buffer())
	var names := env_names.keys()
	names.sort()
	var args := []
	for a: String in OS.get_cmdline_user_args():
		if not _view_only(a):
			args.append(a)
	var extra := [Engine.get_version_info().get("hash", ""), OS.get_name(), OS.has_feature("web"), args]
	for n: String in names:
		extra.append([n, OS.get_environment(n)])
	ctx.update(var_to_bytes(extra))
	_fingerprint = ctx.finish().hex_encode()
	print("LOADING cache fingerprint: %d scripts, %d assets, %d switches, %d ms" % [files.size(), assets.size(), names.size(),
			(Time.get_ticks_usec() - t0) / 1000])
	return _fingerprint


## User arguments that only say where to look or how to draw (never what the world is), so a
## still at another spawn or hour still hits the cache. Anything else counts.
const VIEW_ARGS := ["--spawn=", "--hour=", "--weather=", "--wetness=", "--quality=", "--nohud",
		"--noload", "--stats", "--motionblur=", "--moonage=", "--contrails="]


static func _view_only(arg: String) -> bool:
	for v: String in VIEW_ARGS:
		if arg.begins_with(v):
			return true
	return false


static func _list(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".uid"):
			continue
		out.append(dir_path + "/" + f)
	for d in dir.get_directories():
		_list(dir_path + "/" + d, out)


## The file an entry of `kind` with these `inputs` lives in.
static func path_for(kind: String, inputs: Array) -> String:
	var key := (var_to_bytes([fingerprint(), inputs]) as PackedByteArray)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(key)
	return "%s/%s_%s.bin" % [DIR, kind, ctx.finish().hex_encode()]


## The value stored under `kind` + `inputs` (plain data: arrays, dictionaries, packed arrays,
## maths types - never objects), or null on a miss (or with the cache off).
static func load_data(kind: String, inputs: Array) -> Variant:
	if not enabled():
		return null
	var path := path_for(kind, inputs)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var data: Variant = f.get_var()
	f.close()
	return data


## Stores `data` (plain data, see load_data) under `kind` + `inputs`, and drops all but the newest
## KEEP entries of `kind`.
static func save_data(kind: String, inputs: Array, data: Variant) -> void:
	if not enabled():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_for(kind, inputs)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var(data)
	f.close()
	# Renamed into place whole, so a launch killed mid-write never leaves a half entry behind.
	DirAccess.rename_absolute(tmp, path)
	_trim(kind, path)


## The images stored under `kind` + `inputs`, or [] on a miss (or with the cache off).
static func load_images(kind: String, inputs: Array) -> Array[Image]:
	var out: Array[Image] = []
	var data: Variant = load_data(kind, inputs)
	if not (data is Array):
		return out
	for e: Variant in data:
		if not (e is Array) or (e as Array).size() != 4:
			out.clear()
			return out
		var img := Image.create_from_data(e[0], e[1], false, e[2], e[3])
		if img == null or img.is_empty():
			out.clear()
			return out
		out.append(img)
	return out


## Stores `images` under `kind` + `inputs`.
static func save_images(kind: String, inputs: Array, images: Array) -> void:
	var data := []
	for img: Image in images:
		data.append([img.get_width(), img.get_height(), img.get_format(), img.get_data()])
	save_data(kind, inputs, data)


static func _trim(kind: String, keep_path: String) -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var found: Array = []
	for f in dir.get_files():
		if f.begins_with(kind + "_") and f.ends_with(".bin"):
			var p := DIR + "/" + f
			if p != keep_path:
				found.append([FileAccess.get_modified_time(p), p])
	found.sort()
	found.reverse()
	for i in range(KEEP - 1, found.size()):
		DirAccess.remove_absolute(found[i][1])
