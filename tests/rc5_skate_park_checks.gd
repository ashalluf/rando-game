extends RefCounted
## THE PIT at 16:30 from the deck (RcSkatePark, the skate_park reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the park's concrete pass (look5) is in the shader, off by default and switched on by the
## park's material; the pool's frontside air now clears the coping by most of a metre and the
## camera row's skate_t holds the first rider at its top; the boardwalk's painted boards and murals
## are lit paint (not unshaded) and faded; the camera row stands on the high deck by the pool;
## RC5_SKATE=0 puts the old numbers back.

var _t: Object


func run(t: Object) -> void:
	_t = t
	var was := RcSkatePark.enabled
	RcSkatePark.enabled = true
	_shader()
	_air()
	_paint()
	_camera()
	RcSkatePark.enabled = false
	_t._check(is_equal_approx(RcSkatePark.pool_air(), RcSkatePark.POOL_AIR_OLD)
		and (RcSkatePark.paint(Color(0.9, 0.2, 0.3)) as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"RC5_SKATE=0: the old pool air and the old unshaded boards")
	var m := ShaderMaterial.new()
	RcSkatePark.apply(m)
	_t._check(float(m.get_shader_parameter("look5")) == 0.0, "RC5_SKATE=0: the park's concrete pass is off")
	RcSkatePark.enabled = was


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/skate_park.gdshader")
	_t._check(src.contains("uniform float look5 = 0.0;"), "the park's concrete pass is off by default (the A/B)")
	for f: String in ["deck_used(", "bowl_used(", "coping_used("]:
		_t._check(src.count(f) == 2, "the shader defines and calls %s)" % f)
	var rx := RegEx.create_from_string("\\bpatch\\b")
	_t._check(rx.search(src) == null, "no GLSL reserved word 'patch' in the shader")
	var m := ShaderMaterial.new()
	RcSkatePark.apply(m)
	_t._check(float(m.get_shader_parameter("look5")) == 1.0, "RcSkatePark.apply() switches the pass on")
	_t._check(FileAccess.get_file_as_string("res://scripts/world/skate_park.gd").contains("RcSkatePark.apply(_material)"),
		"the park's material takes the pass")


## The pool line's frontside air: over the deck by most of a metre at its top (it cleared it by a
## hand, so the rider read as standing on the deck).
func _air() -> void:
	var life: GDScript = load("res://scripts/world/skate_park_life.gd")
	var src := FileAccess.get_file_as_string("res://scripts/world/skate_park_life.gd")
	_t._check(src.contains("h = RcSkatePark.pool_air()"), "the pool line's air takes RcSkatePark.pool_air()")
	_t._check(RcSkatePark.pool_air() > RcSkatePark.POOL_AIR_OLD + 0.5, "the pool air is higher than it was")
	# The table may be cached from an earlier file: measure from a fresh sample.
	var tables: Dictionary = life.get("_tables")
	var cached: Variant = tables.get("pool")
	tables.erase("pool")
	var top := -INF
	var t := 0.0
	while t < 13.0:
		var r: Array = life.call("at", "pool", t)
		if int(r[1]) == 2:
			top = maxf(top, (r[0] as Transform3D).origin.y)
		t += 0.05
	_t._check(top > SkatePark.H_HI + 0.7, "the pool air's board clears the deck by %.2f m (> 0.7)" % [top - SkatePark.H_HI])
	if cached != null:
		tables["pool"] = cached


func _paint() -> void:
	var m := RcSkatePark.paint(Color(0.68, 0.30, 0.82))
	_t._check(m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "the boardwalk's painted boards are lit paint")
	_t._check(m.albedo_color.s < Color(0.68, 0.30, 0.82).s, "and a little faded by the sun")
	_t._check(m == RcSkatePark.paint(Color(0.68, 0.30, 0.82)), "one material a colour")
	var src := FileAccess.get_file_as_string("res://scripts/world/landmark_venice_boardwalk.gd")
	_t._check(src.count("RcSkatePark.paint(") == 6 and not src.contains("0.85, true)"),
		"every board, mural, hoarding and art-wall panel takes it")


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (parsed as Dictionary).get("cameras", []):
		if c.get("name", "") == "skate_park":
			row = c
	_t._check(not row.is_empty() and row.has("skate_t"), "the skate_park camera row exists and stages the riders' clock")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var local := Vector2(float(eye[0]) + 978.3, float(eye[2]) + 473.6)
	_t._check(absf(local.x) < SkatePark.HALF_W and local.y < 0.0 and local.y > -SkatePark.HALF_L,
		"the eye stands over the high deck (park-local %.1f, %.1f)" % [local.x, local.y])
	var life: GDScript = load("res://scripts/world/skate_park_life.gd")
	var r0: Array = (life.get_script_constant_map()["RIDERS"] as Array)[0]
	var at: Array = life.call("at", String(r0[0]), float(row.skate_t) * float(r0[2]) + float(r0[1]))
	_t._check(int(at[1]) == 2 and (at[0] as Transform3D).origin.y > SkatePark.H_HI + 0.6,
		"at skate_t the first pool rider is in the air over the coping")
