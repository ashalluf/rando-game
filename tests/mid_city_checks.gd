extends RefCounted
## The mid distance (MidCity, docs/HANDOFF.md "The mid distance"): checks for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Every check builds its own captures
## from the plan (CityChunk.capturing, the far city's own path): nothing leans on where an earlier
## check left the player or the streamer. Under --headless no shader runs; the shaders' sources are
## read to keep the far cars' keys on the night lights'. tools/mid_city/probe.gd prints the same
## numbers round a point; the stills are in the HANDOFF section.

var _t: Node
## Suburb and beach-town blocks of the default seed (tools/mid_city/probe.gd -- --at=-500,200).
const BLOCKS := [Vector2i(-7, -1), Vector2i(-6, -1), Vector2i(-6, 0), Vector2i(-6, 1), Vector2i(-5, 0), Vector2i(-5, 1)]


func run(t: Node, city: Node3D) -> void:
	_t = t
	var streamer := city as CityStreamer
	if streamer == null:
		_t._check(false, "mid city: the city scene is a CityStreamer")
		return
	var was := MidCity.enabled
	MidCity.enabled = true
	_yard_trees(streamer)
	_houses_and_pools(streamer)
	_nothing_moved(streamer)
	MidCity.enabled = was
	_shaders()


func _capture(streamer: CityStreamer, k: Vector2i) -> CityChunk:
	var cap := CityChunk.new()
	cap.plan = streamer.plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = streamer.chunk_style()
	cap.capturing = true
	cap.build()
	return cap


func _plant(streamer: CityStreamer, k: Vector2i, cap: CityChunk) -> Array:
	var veg := []
	var cols := []
	var cus := []
	MidCity.yard_trees(streamer.plan, k, streamer.plan.block(k.x, k.y), cap.captured, cap._gy,
		func(q: Vector2) -> bool: return cap._under_freeway(q, CityChunk.TREE_FREEWAY_MARGIN), veg, cols, cus)
	return [veg, cols, cus]


## The yards get trees, at the district's share, on green ground and never in a building; the same
## trees every time; none with the switch off.
func _yard_trees(streamer: CityStreamer) -> void:
	var total := 0
	var inside := 0
	var real := true
	var same := true
	var off := 0
	var blocks := 0
	for k: Vector2i in BLOCKS:
		var b := streamer.plan.block(k.x, k.y)
		if streamer.plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			continue
		blocks += 1
		var cap := _capture(streamer, k)
		var got := _plant(streamer, k, cap)
		var again := _plant(streamer, k, cap)
		if (got[0] as Array) != (again[0] as Array):
			same = false
		var feet: Array[Rect2] = []
		var lb: Dictionary = (cap.captured.batch as Dictionary).get("lod_box", {"xforms": []})
		for xf: Transform3D in lb.xforms:
			feet.append(MidCity._footprint(xf))
		for i in (got[0] as Array).size():
			var xf: Transform3D = got[0][i]
			var p := Vector2(xf.origin.x, xf.origin.z)
			for f: Rect2 in feet:
				if f.has_point(p):
					inside += 1
					break
			if not is_equal_approx((got[2][i] as Color).r, 1.0):
				real = false
		total += (got[0] as Array).size()
		MidCity.enabled = false
		off += (_plant(streamer, k, cap)[0] as Array).size()
		MidCity.enabled = true
		cap.free()
	_t._check(blocks >= 4 and total >= blocks * 6 and inside == 0 and real and same and off == 0,
		"mid city: yard trees in the suburbs and beach town (%d over %d blocks, %d inside a building, on the real ground %s, the same twice %s, %d with MID_CITY=0)" % [total, blocks, inside, str(real), str(same), off])


## A house wing's box and its pitched slabs carry their flags; the clay roofs are their own tints,
## not one orange; the yards' pools are boxes; off, the old flags and colours and no pools.
func _houses_and_pools(streamer: CityStreamer) -> void:
	var walls := 0
	var slabs := 0
	var pools := 0
	var clays := {}
	var off_flags := 0
	for k: Vector2i in BLOCKS:
		var cap := _capture(streamer, k)
		var lb: Dictionary = (cap.captured.batch as Dictionary).get("lod_box", {"xforms": [], "colors": [], "custom": []})
		for i in (lb.custom as Array).size():
			var c: Color = lb.custom[i]
			if is_equal_approx(c.a, MidCity.HOUSE_FLAG):
				walls += 1
			elif is_equal_approx(c.a, MidCity.ROOF_FLAG):
				slabs += 1
				var col: Color = lb.colors[i]
				if col.r - col.b > 0.22:
					clays[col.to_html()] = true
			elif is_equal_approx(c.a, MidCity.POOL_FLAG):
				pools += 1
		cap.free()
		MidCity.enabled = false
		var old := _capture(streamer, k)
		var ob: Dictionary = (old.captured.batch as Dictionary).get("lod_box", {"custom": []})
		for c: Color in ob.custom:
			if is_equal_approx(c.a, MidCity.HOUSE_FLAG) or is_equal_approx(c.a, MidCity.ROOF_FLAG) or is_equal_approx(c.a, MidCity.POOL_FLAG):
				off_flags += 1
		old.free()
		MidCity.enabled = true
	_t._check(walls >= 20 and slabs >= 20 and clays.size() >= 2 and pools >= 2 and off_flags == 0,
		"mid city: house wings and roof slabs flagged for the far shader (%d, %d), %d clay roof colours, %d pools; %d flags with MID_CITY=0" % [walls, slabs, clays.size(), pools, off_flags])


## Turning it on moves nothing the block builds: the same boxes in the same order, the pools added.
func _nothing_moved(streamer: CityStreamer) -> void:
	var moved := 0
	var count := 0
	for k: Vector2i in BLOCKS:
		var on := _capture(streamer, k)
		MidCity.enabled = false
		var off := _capture(streamer, k)
		MidCity.enabled = true
		var a: Array = []
		var lb: Dictionary = (on.captured.batch as Dictionary).get("lod_box", {"xforms": [], "custom": []})
		for i in (lb.xforms as Array).size():
			if not is_equal_approx((lb.custom[i] as Color).a, MidCity.POOL_FLAG):
				a.append(lb.xforms[i])
		var bb: Array = ((off.captured.batch as Dictionary).get("lod_box", {"xforms": []}) as Dictionary).xforms
		count += bb.size()
		if a.size() != bb.size():
			moved += absi(a.size() - bb.size())
		else:
			for i in a.size():
				if not (a[i] as Transform3D).is_equal_approx(bb[i]):
					moved += 1
		if (on.captured.ground as Array).size() != (off.captured.ground as Array).size():
			moved += 1
		on.free()
		off.free()
	_t._check(count > 100 and moved == 0, "mid city: the blocks' far boxes and ground are the same with it on and off, less the pools (%d boxes, %d moved)" % [count, moved])


## The shaders carry the switch, and the day cars are the night lights' own (far_traffic's keys).
func _shaders() -> void:
	var cars := FileAccess.get_file_as_string("res://shaders/far_cars.gdshaderinc")
	var traffic := FileAccess.get_file_as_string("res://shaders/far_traffic.gdshaderinc")
	var lod := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var ground := FileAccess.get_file_as_string("res://shaders/far_ground.gdshader")
	var canopy := FileAccess.get_file_as_string("res://shaders/far_canopy.gdshader")
	var key := "lane * 7.0 + (sgn > 0.0 ? 3.0 : 0.0)"
	var ok := cars.contains(key) and traffic.contains(key) and cars.contains("ft_hash(key + 11.7) * (FT_CELL - 5.6)") \
		and traffic.contains("ft_hash(key + 11.7) * (FT_CELL - 5.6)") and cars.contains("mix(10.0, 15.0, busy)") and traffic.contains("mix(10.0, 15.0, busy)")
	var wired := lod.contains("far_cars.gdshaderinc") and ground.contains("far_cars.gdshaderinc") \
		and lod.contains("uniform bool mid_city") and ground.contains("uniform bool mid_city") and canopy.contains("uniform bool mid_city") \
		and lod.contains("abs(custom.a - 0.25)") and lod.contains("abs(custom.a - 1.25)") and lod.contains("custom.a > 4.5")
	var mat_on: bool = PropFactory.building_lod_material().get_shader_parameter("mid_city") == MidCity.enabled \
		and PropFactory.far_ground_material().get_shader_parameter("mid_city") == MidCity.enabled
	_t._check(ok and wired and mat_on and is_equal_approx(MidCity.HOUSE_FLAG, 0.25) and is_equal_approx(MidCity.ROOF_FLAG, 1.25) and is_equal_approx(MidCity.POOL_FLAG, 5.0),
		"mid city: far_cars' moving cars are far_traffic's (keys %s), the shaders read the flags (%s), the materials carry the switch (%s)" % [str(ok), str(wired), str(mat_on)])
