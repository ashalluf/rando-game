extends RefCounted
## The yard_sale refcam (Rc5YardSale, wave 8) for tests/smoke_test.gd. Loaded at run time (not
## named there), so it compiles after the autoloads. Checks: the camera row (Saturday 09:30 clear,
## staged by its "yard_sale" key, parked cars by the lens cleared); the canopy and blanket meshes
## build inside their budgets on the kit's one material at their real size; a six-foot table of
## goods carries more than the old one-row table; the plan offers the new kinds only while the pass
## is on, they appear on a share of the suburbs' Saturday sales and keep the row's clearances; the
## camera's own block holds a sale with a canopy. Everything it needs is staged here (the statics
## are put back).

const NEAR := Vector2(1072, 3870)

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	var saved := [YardSales.enabled, YardSales.force_all, YardSales.force_day, YardSales.force_hour, Rc5YardSale.enabled]
	YardSales.enabled = true
	YardSales.force_all = false
	_row()
	_kit()
	_plan(city.plan)
	YardSales.enabled = saved[0]
	YardSales.force_all = saved[1]
	YardSales.force_day = saved[2]
	YardSales.force_hour = saved[3]
	Rc5YardSale.enabled = saved[4]
	print("RC5_YARD_SALE_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _tris(m: Mesh) -> int:
	var tris := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


func _row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row := {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if String(c.get("name", "")) == "yard_sale":
				row = c
	_check(not row.is_empty() and int(row.get("yard_sale", 0)) == 1 and is_equal_approx(float(row.get("hour", 0)), 9.5)
		and String(row.get("weather", "")) == "clear" and float(row.get("clear_cars", 0)) > 0.0,
		"rc5 yard sale: the camera row is a Saturday 09:30 clear, staged, the lens clear of parked cars (%s)" % str(row.keys()))


func _kit() -> void:
	Rc5YardSale.enabled = true
	var mat := YardSaleKit.material()
	var bad: Array = []
	for k: String in ["canopy_0_0", "canopy_4_2", "blanket_0", "blanket_1"]:
		var m: Mesh = YardSaleKit.get_mesh(k)
		var n := _tris(m) if m else 0
		if m == null or n < 200 or n > 6000 or m.surface_get_material(0) != mat:
			bad.append("%s %d" % [k, n])
	_check(bad.is_empty(), "rc5 yard sale: the canopy and blanket build inside their budgets on the kit's material %s" % str(bad))
	var c := YardSaleKit.get_mesh("canopy_1_1").get_aabb()
	var b := YardSaleKit.get_mesh("blanket_0").get_aabb()
	_check(absf(c.size.x - 2.5) < 0.15 and absf(c.end.y - Rc5YardSale.PEAK) < 0.05 and b.end.y < 0.5 and b.size.x > 1.7,
		"rc5 yard sale: the canopy stands 8 ft square and %.2f m to its peak, the blanket lies low (%s, %s)" % [Rc5YardSale.PEAK, str(c), str(b)])
	# Crammed tables: the goods of a six-foot table, built fresh with the pass on and off.
	var on := _tris(YardSaleKit._table6("0"))
	Rc5YardSale.enabled = false
	var off := _tris(YardSaleKit._table6("0"))
	Rc5YardSale.enabled = true
	_check(on > off * 1.15 and on < 9000, "rc5 yard sale: a table of goods carries more than the old one row (%d vs %d triangles)" % [on, off])


func _plan(plan: CityPlan) -> void:
	var c: Vector2i = plan.block_index_at(NEAR)
	var kinds := {}
	var sales := 0
	var camera_canopy := false
	var off_kinds := {}
	for bx in range(c.x - 3, c.x + 4):
		for bz in range(c.y - 3, c.y + 4):
			Rc5YardSale.enabled = true
			for sp: Array in YardSales.block_sales(plan, bx, bz, 6, 9.5):
				sales += 1
				for it: Dictionary in sp[1].items:
					kinds[it.kind] = int(kinds.get(it.kind, 0)) + 1
					if it.kind == "canopy" and bx == c.x and bz == c.y:
						camera_canopy = true
			Rc5YardSale.enabled = false
			for sp: Array in YardSales.block_sales(plan, bx, bz, 6, 9.5):
				for it: Dictionary in sp[1].items:
					off_kinds[it.kind] = true
	Rc5YardSale.enabled = true
	_check(sales >= 6 and int(kinds.get("canopy", 0)) >= 1 and int(kinds.get("blanket", 0)) >= 2 and int(kinds.get("canopy", 0)) < sales,
		"rc5 yard sale: a share of Saturday's sales put up a canopy and spread a blanket (%d sales, %s)" % [sales, str(kinds)])
	_check(not off_kinds.has("canopy") and not off_kinds.has("blanket"), "rc5 yard sale: off, the old kinds only (%s)" % str(off_kinds.keys()))
	_check(camera_canopy, "rc5 yard sale: the camera's block %s holds a sale under a canopy" % str(c))
