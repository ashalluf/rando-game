extends RefCounted
## The load-time checks for tests/smoke_test.gd (docs/HANDOFF.md, "Load time"): the disk cache
## (LoadCache) gives back exactly the bytes a bake wrote, misses on any other input, and the basin
## bake read from it is the bake made fresh; the loading screen still warms every shader. Loaded at
## run time, so it compiles after the autoloads.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_fingerprint()
	_round_trip(plan)
	_far_city(city, plan)
	_warm_up()


func _fingerprint() -> void:
	var a := LoadCache.fingerprint()
	_check(a.length() == 32 and a == LoadCache.fingerprint(), "the load cache's code fingerprint is an md5 and stable within a run")
	_check(LoadCache.path_for("x", [1]) != LoadCache.path_for("x", [2]), "the load cache keys on the caller's inputs")


## A small bake, fresh, then through the cache: the same bytes, both images; another seed misses.
func _round_trip(plan: CityPlan) -> void:
	if plan.macro == null:
		return
	if not LoadCache.enabled():
		_check(true, "the load cache is off (LOAD_CACHE=0): nothing to round-trip")
		return
	var inputs := ["check_bake", plan.seed, 9000.0, 24]
	var img := plan.macro.bake(Vector2(300.0, -200.0), 9000.0, 24)
	var h := plan.macro.bake_height
	LoadCache.save_images("check_bake", inputs, [img, h])
	var back := LoadCache.load_images("check_bake", inputs)
	_check(back.size() == 2, "the load cache gives back both images of a bake")
	if back.size() == 2:
		_check(back[0].get_format() == img.get_format() and back[0].get_size() == img.get_size()
				and back[0].get_data() == img.get_data(), "the cached basin colour is the fresh bake's, byte for byte")
		_check(back[1].get_format() == h.get_format() and back[1].get_size() == h.get_size()
				and back[1].get_data() == h.get_data(), "the cached basin height is the fresh bake's, byte for byte")
	_check(LoadCache.load_images("check_bake", ["check_bake", plan.seed + 1, 9000.0, 24]).is_empty(),
			"the load cache misses for another seed")
	DirAccess.remove_absolute(LoadCache.path_for("check_bake", inputs))


## A far-city tile built fresh is the one the city's Skyline keeps for the disk, and survives the
## disk byte for byte.
func _far_city(city: Node3D, plan: CityPlan) -> void:
	var sky = city.get("_skyline")
	if sky == null or not LoadCache.enabled():
		return
	var stored: Variant = LoadCache.load_data("far_city", sky._disk_inputs())
	var disk: Dictionary = stored if stored is Dictionary else {}
	var tile = null
	for t in disk:
		if disk[t] != null:
			tile = t
			break
	_check(tile != null, "the far city keeps its tiles for the load cache (%d)" % disk.size())
	if tile == null:
		return
	var fresh := Skyline.new()
	fresh.setup(plan, city.call("chunk_style"), null)
	fresh._disk_open = true
	fresh._begin_tile(tile)
	fresh._recording = true
	while not fresh._work_step():
		pass
	var a: Variant = fresh._disk.get(tile)
	_check(a != null and var_to_bytes(a) == var_to_bytes(disk[tile]), "a far-city tile in the load cache is the tile built fresh now, byte for byte")
	LoadCache.save_data("check_far", [plan.seed], a)
	var back: Variant = LoadCache.load_data("check_far", [plan.seed])
	_check(back != null and var_to_bytes(back) == var_to_bytes(a), "a far-city tile survives the disk byte for byte")
	DirAccess.remove_absolute(LoadCache.path_for("check_far", [plan.seed]))
	fresh.free()


## The batched shader warm-up still draws every .gdshader (LoadingScreen._shader_files()).
func _warm_up() -> void:
	var screen := LoadingScreen.new()
	var files := screen._shader_files()
	var n := 0
	for f in DirAccess.get_files_at("res://shaders"):
		if f.trim_suffix(".remap").ends_with(".gdshader"):
			n += 1
	_check(files.size() == n and n > 0 and screen.shader_batch >= 1, "the loading screen warms every shader (%d) in batches" % n)
	screen.free()
