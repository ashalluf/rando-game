extends RefCounted
## The farmers' market refcam (fleet wave 8, rc5-farmers-market; docs/HANDOFF.md "The farmers'
## market from the aisle"): checks for tests/smoke_test.gd. CPU only (no pixel is read headless):
##   * the farmers_market row is in tools/refcams/cameras_w8.json at 10:00 clear with market_day,
##     and its eye stands in a market's aisle on that market's street;
##   * produce heaps are packed (more fruit on a crate than the old grid) and each produce table
##     stays under a triangle budget, its far level as light as before;
##   * the cartons carry their print and tape (more triangles than a plain box);
##   * the material's switches are at their new values, and the busy market has more shoppers.
## RC5_MARKET=0 is the A/B (FarmersMarketKit.rc5 false: the kit as it was).

var _t: Object

## Triangles a produce table may hold near.
const TABLE_BUDGET := 14000


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan") if city else null
	_camera_row(plan)
	if not FarmersMarketKit.rc5:
		_t._check(true, "rc5-farmers-market: off (RC5_MARKET=0)")
		return
	_produce()
	_cartons()
	_material()
	_shoppers()


func _camera_row(plan: CityPlan) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	_t._check(f != null, "rc5-farmers-market: tools/refcams/cameras_w8.json exists")
	if f == null:
		return
	var table: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	if table is Dictionary:
		for cam: Dictionary in (table as Dictionary).get("cameras", []):
			if String(cam.get("name", "")) == "farmers_market":
				row = cam
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 10.0)
		and String(row.get("weather", "")) == "clear" and int(row.get("market_day", 0)) == 1,
		"rc5-farmers-market: the camera row is at 10:00 clear on a market day")
	if row.is_empty() or plan == null or not FarmersMarket.enabled:
		return
	var eye: Array = row.eye
	var at := Vector2(float(eye[0]), float(eye[2]))
	var m := FarmersMarket.decide(plan, FarmersMarket._cell_of(at))
	var inside := false
	if not m.is_empty():
		var along: Vector2 = FarmersMarket.dirs(m)[0]
		var across: Vector2 = FarmersMarket.dirs(m)[1]
		var lay := FarmersMarket.layout(m)
		var o0 := FarmersMarket.point(m, 0.0, 0.0)
		var t := (at - o0).dot(along)
		var o := (at - o0).dot(across)
		inside = t > float(lay.len0) and t < float(lay.len1) and absf(o) < float(m.width) * 0.25
	_t._check(inside, "rc5-farmers-market: the eye stands in the market's aisle (%s)" % [at])


func _tris(mesh: Mesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _produce() -> void:
	var worst := 0
	for v in int(FarmersMarketKit.VARIANTS[0]):
		worst = maxi(worst, _tris(FarmersMarketKit.goods(0, v)))
	_t._check(worst > 10000 and worst < TABLE_BUDGET,
		"rc5-farmers-market: produce tables are finer and packed, under budget (%d near, budget %d)" % [worst, TABLE_BUDGET])
	# A crate's heap: count the fruit in one oranges crate on the old and the new path.
	var counts := []
	for on: bool in [false, true]:
		FarmersMarketKit.rc5 = on
		var g := FarmersMarketKit.Geo.new()
		g.mode = 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var before := g.v.size()
		FarmersMarketKit._heap(g, Transform3D(), Vector2(0.39, 0.58), 0.195, 0.05, "orange", rng)
		counts.append(g.v.size() - before)
	FarmersMarketKit.rc5 = true
	_t._check(int(counts[1]) > int(counts[0]) * 2,
		"rc5-farmers-market: a crate's heap is packed fuller than the old grid (%d vertices, was %d)" % [counts[1], counts[0]])
	# The shadow twin (the far level) stays the light one.
	var mesh := FarmersMarketKit.goods(0, 0)
	var twin: Variant = PropFactory._shadow_proxies.get(mesh)
	_t._check(twin is Mesh and _tris(twin as Mesh) < 4000,
		"rc5-farmers-market: the produce table's shadow twin stays coarse (%d)" % (_tris(twin as Mesh) if twin is Mesh else -1))


func _cartons() -> void:
	var counts := []
	for on: bool in [false, true]:
		FarmersMarketKit.rc5 = on
		var g := FarmersMarketKit.Geo.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		FarmersMarketKit._carton(g, Transform3D(), Vector3(0.45, 0.3, 0.32), Color(0.66, 0.5, 0.33), rng)
		counts.append(g.near.size() / 3)
	FarmersMarketKit.rc5 = true
	_t._check(int(counts[0]) == 10 and int(counts[1]) > 60,
		"rc5-farmers-market: cartons carry tape and print (%d triangles, a plain box %d)" % [counts[1], counts[0]])


func _material() -> void:
	var mat := FarmersMarketKit.material()
	var relief: Variant = mat.get_shader_parameter("skin_relief")
	var drape: Variant = mat.get_shader_parameter("cloth_drape")
	var src := (mat.shader as Shader).code
	_t._check((relief == null or float(relief) > 0.5) and (drape == null or float(drape) > 0.5)
		and src.contains("uniform float skin_relief = 1.0") and src.contains("uniform float cloth_drape = 1.0")
		and src.contains("uniform float bulb_day = 0.18") and src.contains("uniform float grain_along = 1.0"),
		"rc5-farmers-market: the market material's relief, drape, bulb and grain are on")


func _shoppers() -> void:
	_t._check(FarmersMarket.MAX_SHOPPERS > FarmersMarket.MAX_SHOPPERS_OLD and roundi(float(FarmersMarket.MAX_SHOPPERS) * FarmersMarket.busyness(10.0)) >= 40,
		"rc5-farmers-market: a busy Saturday market has more shoppers (%d at 10:00)" % roundi(float(FarmersMarket.MAX_SHOPPERS) * FarmersMarket.busyness(10.0)))
