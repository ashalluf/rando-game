extends RefCounted
## The suburban back yard on a Saturday afternoon (Rc5Backyard, the backyard_pool reference camera
## in tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the camera row stands on a suburb patio with a pool ahead of it; the weekend lunch
## window is the same in GDScript and both shaders, cooks a believable share at 15:00 on a
## Saturday and none on a weekday, and day_hook() hands it to both materials; the traced pool's
## shader and its hooks in YardFill and Backyards; the floats sit in the pool's quad; the
## loungers' umbrella is a pure hash at about its share, behind the side table; the fence pass is
## off by default and on through the walls material; RC5_BACKYARD=0 puts it all back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := Rc5Backyard.enabled
	var was_force := Rc5Backyard.force_weekend
	Rc5Backyard.enabled = true
	var plan: CityPlan = city.plan
	_camera(plan)
	_cooking()
	_pool()
	_umbrella(plan)
	_fence()
	# The A/B: off, nothing is added and the materials are back to the old look.
	Rc5Backyard.enabled = false
	Rc5Backyard.force_weekend = 1
	Rc5Backyard.day_hook(city)
	_t._check(float(BackyardKit.smoke_material().get_shader_parameter("weekend")) == 0.0 and float(BackyardKit.material().get_shader_parameter("weekend")) == 0.0,
		"RC5_BACKYARD=0: no weekend lunch window")
	_t._check(Rc5Backyard.lounger_umbrella(plan.seed, {"at": Vector2(3, 4)}, Transform3D()).is_empty(), "RC5_BACKYARD=0: no loungers' umbrella")
	var wm := ShaderMaterial.new()
	Rc5Backyard.walls_hook(wm)
	_t._check(float(wm.get_shader_parameter("rc5")) == 0.0, "RC5_BACKYARD=0: the fence pass off")
	Rc5Backyard.enabled = was
	Rc5Backyard.force_weekend = was_force
	Rc5Backyard.day_hook(city)


func _row() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	if not data is Dictionary:
		return {}
	for c: Dictionary in data.get("cameras", []):
		if c.name == "backyard_pool":
			return c
	return {}


func _camera(plan: CityPlan) -> void:
	var row := _row()
	_t._check(not row.is_empty(), "the backyard_pool camera row is in cameras_w8.json")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	_t._check(float(row.hour) == 15.0 and String(row.weather) == "clear" and row.get("agl", false),
		"the camera is a 15:00 clear eye-level shot")
	var bi: Vector2i = plan.block_index_at(p)
	var b: Dictionary = plan.block(bi.x, bi.y)
	_t._check(int(b.district) == CityPlan.District.SUBURBS, "the patio is in the suburbs")
	# A yard pool within 8 m ahead of the eye (YardFill's plan of the block).
	var yaw := deg_to_rad(float(eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var found := false
	var lots: Array = plan.lots(bi.x, bi.y)
	if HouseKit.enabled:
		lots.append_array(HouseKit.extra_lots(plan, bi.x, bi.y))
	var entries: Array = []
	for lot: Dictionary in lots:
		if lot.yard or YardFill.is_corridor(plan, lot):
			continue
		entries.append(HouseKit.yard_entry(lot, HouseKit.plan_house(plan, bi.x, bi.y, lot, int(b.district))))
	var bp := YardFill.beach_block(plan, bi.x, bi.y, entries)
	for lp: Dictionary in bp.lots:
		for pc: Array in lp.pieces:
			if int(pc[1]) == YardFill.G_POOL:
				var rel := (pc[0] as Rect2).get_center() - p
				if rel.length() < 8.0 and rel.normalized().dot(fwd) > 0.8:
					found = true
	_t._check(found, "a yard pool lies just ahead of the backyard_pool eye")


func _cooking() -> void:
	for path in ["res://shaders/backyard.gdshader", "res://shaders/backyard_smoke.gdshader"]:
		var s := FileAccess.get_file_as_string(path)
		_t._check(s.contains("uniform float weekend = 0.0;") and s.contains("s < %.1f" % Rc5Backyard.WEEKEND_SHARE)
			and s.contains("mix(%.1f, %.1f, fract(q * 3.17))" % [Rc5Backyard.LUNCH_START.x, Rc5Backyard.LUNCH_START.y])
			and s.contains("mix(%.1f, %.1f, fract(q * 5.71))" % [Rc5Backyard.LUNCH_LEN.x, Rc5Backyard.LUNCH_LEN.y]),
			"%s's lunch window is Rc5Backyard's" % path.get_file())
	var sat := 0
	var wk := 0
	var dinner_same := true
	for i in 2000:
		var seed := float(i) / 2000.0
		if Rc5Backyard.cooking(seed, 15.0, true) > 0.5:
			sat += 1
		if Rc5Backyard.cooking(seed, 15.0, false) > 0.5:
			wk += 1
		if Rc5Backyard.cooking(seed, 19.0, true) < Rc5Backyard.cooking(seed, 19.0, false):
			dinner_same = false
	_t._check(sat > 200 and sat < 800, "on a Saturday at 15:00 some grills are going (%d of 2000)" % sat)
	_t._check(wk == 0, "on a weekday at 15:00 none are")
	_t._check(dinner_same, "the weekend lunch takes nothing from dinner")
	Rc5Backyard.force_weekend = 1
	Rc5Backyard.day_hook(null)
	_t._check(float(BackyardKit.smoke_material().get_shader_parameter("weekend")) == 1.0 and float(BackyardKit.material().get_shader_parameter("weekend")) == 1.0,
		"day_hook() hands a weekend to the smoke and the grills")
	Rc5Backyard.force_weekend = 0
	Rc5Backyard.day_hook(null)
	_t._check(float(BackyardKit.smoke_material().get_shader_parameter("weekend")) == 0.0, "and a weekday")
	Rc5Backyard.force_weekend = -1


func _pool() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/rc5_yard_pool.gdshader")
	_t._check(s.contains("refract(") and s.contains("tank_hit") and s.contains("color_space.gdshaderinc") and s.contains("EMISSION = cs_out("),
		"the yard pool traces its tank and emits in linear on both renderers")
	_t._check(Rc5Backyard.pool_material().shader != null and Rc5Backyard.pool_material().shader.get_shader_uniform_list().size() >= 8,
		"the yard pool's shader loads")
	var yf := FileAccess.get_file_as_string("res://scripts/world/yard_fill.gd")
	_t._check(yf.contains("Rc5Backyard.pool(ch, r)") and yf.contains("Rc5Backyard.commit_pools(ch)") and yf.contains("Rc5Backyard.walls_hook(mat)"),
		"YardFill hands its pools and walls material over")
	_t._check(is_equal_approx(Rc5Backyard.POOL_TOP, YardFill.LIFT + 0.06), "the pool's quad is at the coping's top")
	_t._check(Rc5Backyard.FLOAT_LIFT < Rc5Backyard.POOL_TOP and Rc5Backyard.FLOAT_LIFT > Rc5Backyard.POOL_TOP - 0.03,
		"the floats sit a little into the pool's quad")


func _umbrella(plan: CityPlan) -> void:
	var n := 0
	var ok := true
	var xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(10, 0.3, 20))
	for i in 400:
		var it := {"at": Vector2(float(i) * 3.7, float(i % 17) * 5.1)}
		var a := Rc5Backyard.lounger_umbrella(plan.seed, it, xf)
		var b := Rc5Backyard.lounger_umbrella(plan.seed, it, xf)
		if a.size() != b.size():
			ok = false
		if not a.is_empty():
			n += 1
			var ux: Transform3D = a[0][2]
			if not (a[0][0] == "by_umbrella" and (xf.affine_inverse() * ux.origin).distance_to(Rc5Backyard.UMBRELLA_AT) < 0.01):
				ok = false
	_t._check(ok, "the loungers' umbrella is a pure hash, planted behind the side table")
	_t._check(n > 180 and n < 300, "about LOUNGER_UMBRELLA of the pairs get one (%d of 400)" % n)


func _fence() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/lot_walls.gdshader")
	_t._check(s.contains("uniform float rc5 = 0.0;") and s.contains("if (rc5 > 0.5 && !top)"), "the fence pass is off by default")
	var wm := ShaderMaterial.new()
	Rc5Backyard.walls_hook(wm)
	_t._check(float(wm.get_shader_parameter("rc5")) == 1.0, "the walls material carries the fence pass")
