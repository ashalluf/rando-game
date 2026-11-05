extends RefCounted
## The four-level stack from the air (fleet wave 7, rc4-stack-aerial; docs/HANDOFF.md "The four-level
## stack from the air"): checks for tests/smoke_test.gd. CPU only (no pixel is read headless):
##   * the stack_aerial row is in tools/refcams/cameras_w7.json at 17:30 clear;
##   * the right of way's shade follows the deck's clearance: full under a main line, none under a
##     connector 30 m up (RcStack.bareness);
##   * every planted tree's crown clears the deck over it, and none stands under a main line;
##   * the planting is pure (the same spots twice) and a FULL chunk at the stack plants it;
##   * a tall column is drawn thicker, inside the clearance FreewayStack keeps round it;
##   * the connectors carry more cars at rush hour than at night.
## RC4_STACK=0 is the A/B (the old shade, no planting, the old columns and counts).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	var plan: CityPlan = city.get("plan") if city else null
	if plan == null or plan.macro == null or plan.macro.freeway == null or plan.macro.freeway.stack == null:
		_t._check(true, "rc4-stack-aerial: no stack on this plan (STACK=0)")
		return
	if not RcStack.enabled:
		_t._check(true, "rc4-stack-aerial: off (RC4_STACK=0)")
		return
	_shade()
	_traffic()
	_columns(plan)
	_planting(city, plan)


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "stack_aerial":
				found = absf(float(c.hour) - 17.5) < 0.01 and String(c.get("weather", "")) == "clear" and float(c.eye[1]) >= 120.0
	_t._check(found, "rc4-stack-aerial: the stack_aerial row is in cameras_w7.json, 150 m up at 17:30 clear")


func _shade() -> void:
	var low := {"a": Vector2(0, -50), "b": Vector2(0, 50), "ha": 9.5, "hb": 9.5, "width": 30.0}
	var high := {"a": Vector2(0, -50), "b": Vector2(0, 50), "ha": 32.0, "hb": 32.0, "width": 11.8, "link": true}
	var under_low := RcStack.bareness([low], Vector2(0, 0), 0.0, YardFill.BARE_FADE)
	var under_high := RcStack.bareness([high], Vector2(0, 0), 0.0, YardFill.BARE_FADE)
	var away := RcStack.bareness([low], Vector2(40, 0), 0.0, YardFill.BARE_FADE)
	var old := YardFill._bareness([low], Vector2(0, 0))
	_t._check(under_low > 0.99 and absf(under_low - old) < 0.001 and under_high < 0.01 and away < 0.01,
		"rc4-stack-aerial: the deck's shade is full under a main line (as before), none under a 30 m connector or 40 m off (%.2f %.2f %.2f)" % [under_low, under_high, away])


func _traffic() -> void:
	var night := RcStack.cars_per_link(4, 3.0)
	var day := RcStack.cars_per_link(4, 12.0)
	var rush := RcStack.cars_per_link(4, 17.5)
	_t._check(night < day and day < rush and rush >= 9 and night >= 1,
		"rc4-stack-aerial: a connector carries more cars at 17:30 than at noon, and fewest at night (%d %d %d)" % [night, day, rush])


func _columns(plan: CityPlan) -> void:
	var st: FreewayStack = plan.macro.freeway.stack
	var worst := 0.0
	var thicker := 0
	for c: Dictionary in st.columns(plan):
		var r := RcStack.column_r(c)
		var base_r: float = c.r
		worst = maxf(worst, r - base_r)
		if r > base_r + 0.05:
			thicker += 1
	_t._check(thicker > 0 and worst < 0.8, "rc4-stack-aerial: tall columns are drawn thicker (%d) inside the 0.8 m clearance FreewayStack keeps (+%.2f m)" % [thicker, worst])


func _planting(city: Node3D, plan: CityPlan) -> void:
	var st: FreewayStack = plan.macro.freeway.stack
	var fw: Freeway = plan.macro.freeway
	var c := plan.block_index_at(st.centre)
	var list := RcStack.spots(plan, c.x, c.y)
	RcStack._cache.erase("%d_%d_%d" % [plan.seed, c.x, c.y])
	var again := RcStack.spots(plan, c.x, c.y)
	var same := list.size() == again.size()
	for i in mini(list.size(), again.size()):
		same = same and (list[i][0] as Vector2).is_equal_approx(again[i][0])
	var trees := 0
	var bad := 0
	for s: Array in list:
		if int(s[1]) != 0:
			continue
		trees += 1
		var p: Vector2 = s[0]
		var room := RcStack.clearance(fw, p, float(s[4]) + 1.0, float(plan.height_at(p)))
		if room < float(s[3]) + RcStack.TREE_CLEAR - 0.01:
			bad += 1
	_t._check(trees > 20 and bad == 0 and same,
		"rc4-stack-aerial: the stack's right of way is planted (%d trees), every crown clear of the deck over it (%d not), the same spots twice" % [trees, bad])
	var chunk: CityChunk = city._new_chunk(plan.chunk_index_at(st.centre), CityChunk.Level.FULL)
	chunk.build()
	var counts: Array = chunk.get_meta("rc4_stack_counts", [0, 0])
	var la := 0
	for e: Array in chunk.get_meta("la_at", []):
		if int(e[0]) in RcStack.SPECIES:
			la += 1
	_t._check(int(counts[0]) > 20 and la >= int(counts[0]) and int(counts[1]) > 0,
		"rc4-stack-aerial: a FULL chunk at the stack plants its groves and shrubs (%d trees, %d shrubs, %d LaTrees)" % [int(counts[0]), int(counts[1]), la])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
