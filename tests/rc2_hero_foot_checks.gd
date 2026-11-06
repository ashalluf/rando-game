extends RefCounted
## The on-foot camera refcam (wave 5, rc2-hero-foot), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## The camera row (tools/refcams/cameras_w5.json, its "hero" staging). CameraFade: the three tree
## shaders dither out what is within cf_far of the camera and never in the directional shadow
## pass, the tree materials carry the numbers, the scanned bark its pixel-dither distance fade,
## the switch off marks nothing. ShopCrowd: the gain by distance, the shop weight a FULL block
## keeps in its BusyStreets entry, the steps only for shopping districts, the switch. Pure where
## it can be; the city's FULL chunks are only read.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	_camera_row()
	_camera_fade()
	_shop_crowd(city)


func _camera_row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if c.get("name", "") == "hero_foot":
				row = c
	_t._check(not row.is_empty() and row.get("hero", null) is Dictionary and (row.eye as Array).size() == 5,
		"rc2_hero_foot: cameras_w5.json has the hero_foot row with its hero staging")
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 13.5 and String(row.get("weather", "")) == "clear",
		"rc2_hero_foot: hero_foot is 13:30, clear")


func _camera_fade() -> void:
	for path in ["res://shaders/foliage_tex.gdshader", "res://shaders/foliage.gdshader", "res://shaders/la_tree.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		var frag := src.find("void fragment() {")
		_t._check(src.contains("#include \"res://shaders/camera_fade.gdshaderinc\"") and frag > 0
			and src.find("cf_gone(VERTEX, FRAGCOORD.xy, PROJECTION_MATRIX)", frag) - frag < 40,
			"CameraFade: %s discards near the camera first thing in its fragment" % path.get_file())
	var inc := FileAccess.get_file_as_string("res://shaders/camera_fade.gdshaderinc")
	_t._check(inc.contains("proj[3][3] > 0.5") and inc.contains("cf_far <= 0.0"),
		"CameraFade: never in the directional shadow pass, off at cf_far 0 (the shader's default)")
	_t._check(CameraFade.NEAR < CameraFade.FAR and CameraFade.FAR < 3.8,
		"CameraFade: the fade ends inside the aiming camera's 3.8 m (the hero's own tree never fades)")
	# A tree material made through TreesCloseup carries the numbers.
	var palm: Material = PropFactory.foliage_material()
	if palm is ShaderMaterial and CameraFade.enabled:
		_t._check(is_equal_approx(float((palm as ShaderMaterial).get_shader_parameter("cf_far")), CameraFade.FAR),
			"CameraFade: the palms' material fades near the camera")
	var mesh := PropFactory.model_tree(0)
	var bark_ok := false
	var leaf_ok := false
	if mesh:
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var b := m as StandardMaterial3D
				bark_ok = bark_ok or (b.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
					and is_equal_approx(b.distance_fade_max_distance, CameraFade.FAR))
			elif m is ShaderMaterial:
				leaf_ok = leaf_ok or is_equal_approx(float((m as ShaderMaterial).get_shader_parameter("cf_far")), CameraFade.FAR)
	if CameraFade.enabled:
		_t._check(leaf_ok, "CameraFade: the street tree's leaves fade near the camera")
		_t._check(bark_ok, "CameraFade: the street tree's bark takes the pixel-dither distance fade")
	# The switch.
	var was := CameraFade.enabled
	CameraFade.enabled = false
	var fresh := StandardMaterial3D.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/la_tree.gdshader")
	CameraFade.mark(fresh)
	CameraFade.mark(sm)
	CameraFade.enabled = was
	_t._check(fresh.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and (sm.get_shader_parameter("cf_far") == null or float(sm.get_shader_parameter("cf_far")) == 0.0),
		"CAMERA_FADE=0 marks nothing")


func _shop_crowd(city: Node3D) -> void:
	if not ShopCrowd.enabled:
		_t._check(ShopCrowd.gain([Rect2(), 3.0, 20, 1.2], 0.0) == 1.0, "SHOP_CROWD=0: no gain")
		return
	ShopCrowd.force_in_test = true
	var entry := [Rect2(0, 0, 100, 100), 3.0, 20, 1.2]
	_t._check(is_equal_approx(ShopCrowd.gain(entry, 10.0), 2.2) and is_equal_approx(ShopCrowd.gain(entry, ShopCrowd.FAR + 1.0), 1.0),
		"ShopCrowd: full gain near the camera, none past FAR")
	var mid := ShopCrowd.gain(entry, (ShopCrowd.NEAR + ShopCrowd.FAR) * 0.5)
	_t._check(mid > 1.0 and mid < 2.2, "ShopCrowd: it fades between NEAR and FAR (%.2f)" % mid)
	_t._check(ShopCrowd.gain([Rect2(), 3.0, 20], 0.0) == 1.0, "ShopCrowd: an entry it never weighed keeps its plan")
	var was := ShopCrowd.enabled
	ShopCrowd.enabled = false
	var off := ShopCrowd.gain(entry, 0.0)
	var no_steps := ShopCrowd.steps(city, {"kind": CityPlan.BlockKind.BUILDINGS, "district": CityPlan.District.MIDTOWN, "rect": Rect2()}).size()
	ShopCrowd.enabled = was
	_t._check(off == 1.0 and no_steps == 0, "SHOP_CROWD=0 adds no walkers")
	if ShopCrowd.enabled and BusyStreets.enabled:
		var n := ShopCrowd.steps(city, {"kind": CityPlan.BlockKind.BUILDINGS, "district": CityPlan.District.MIDTOWN, "rect": Rect2()}).size()
		var sub := ShopCrowd.steps(city, {"kind": CityPlan.BlockKind.BUILDINGS, "district": CityPlan.District.SUBURBS, "rect": Rect2()}).size()
		var park := ShopCrowd.steps(city, {"kind": CityPlan.BlockKind.PARK, "district": CityPlan.District.MIDTOWN, "rect": Rect2()}).size()
		_t._check(n == ShopCrowd.MAX_EXTRA + 1 and sub == 0 and park == 0,
			"ShopCrowd: steps for a midtown buildings block only (%d, suburbs %d, park %d)" % [n, sub, park])
	ShopCrowd.force_in_test = false
	# Every weighed entry of the city's FULL chunks is inside 0 .. gain - 1.
	var weighed := 0
	var inside := true
	for k in city.get("chunks"):
		var ch: Node3D = city.chunks[k]
		if not is_instance_valid(ch) or not ch.has_meta("busy_crowd"):
			continue
		for e: Array in ch.get_meta("busy_crowd"):
			if e.size() >= 4:
				weighed += 1
				inside = inside and float(e[3]) >= 0.0 and float(e[3]) <= 1.6
	_t._check(inside, "ShopCrowd: every block's shop weight is in range (%d weighed)" % weighed)
