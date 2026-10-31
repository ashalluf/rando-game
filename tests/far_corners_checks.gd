extends RefCounted
## The far boxes' cut corners (FarBuilding.corners, docs/HANDOFF.md "Cut corners on the far
## boxes"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads.
## Under --headless no shader runs, so the vertex reshape is mirrored here line for line
## (`_reshape()`, building_lod.gdshader's first branch in vertex()) and the source is read to keep
## the two together; tools/glshot/far_building_shot.gd CHAMFER=1 shows the pixels.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_pieces_follow_the_parts()
	_pieces_make_the_near_prism()
	_shader_has_the_reshape()
	_captured_blocks_keep_the_pieces(city)


## Every cut part keeps its own entry (the middle piece) at its index and gets exactly two end
## pieces after everything else, same box and code; an uncut part is one whole box. Off, none.
func _pieces_follow_the_parts() -> void:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var cut_parts := 0
	var wrong: Array[String] = []
	var off_extra := 0
	var was: bool = FarBuilding.corners
	for i in 24:
		var b: Building = scene.instantiate()
		b.seed = 7100 + i * 97
		b.lot_size = Vector2(34.0 + float(i % 4) * 6.0, 32.0 + float(i % 3) * 8.0)
		b.min_height = 20.0 + float(i % 5) * 15.0
		b.max_height = b.min_height * 1.7
		b.chamfer_chance = 1.0
		b.podium_lot = i % 3 == 0
		b.plinth_depth = 0.5
		var style := b.plan_only()
		FarBuilding.corners = true
		var boxes := FarBuilding.boxes(b, style, b.plinth_depth)
		FarBuilding.corners = false
		var plain := FarBuilding.boxes(b, style, b.plinth_depth)
		FarBuilding.corners = was
		var ends: Dictionary = {}
		for e: Array in boxes:
			var c: Color = e[2]
			if is_equal_approx(c.a, FarBuilding.PART_FLAG) and c.r > 1.5:
				var key: Transform3D = e[0]
				ends[key] = int(ends.get(key, 0)) + (1 if c.r < 2.5 else 10)
		var want := 0
		for pi in b.parts.size():
			var grid := b.part_grid(b.parts[pi], style)
			var cut := float(grid.cut_x) > 0.0
			var c: Color = boxes[pi][2]
			var xf: Transform3D = boxes[pi][0]
			if not xf.is_equal_approx(plain[pi][0]):
				wrong.append("seed %d part %d moved" % [b.seed, pi])
			if is_equal_approx(c.r, FarBuilding.PIECE_MIDDLE) != cut or (not cut and not is_equal_approx(c.r, FarBuilding.PIECE_WHOLE)):
				wrong.append("seed %d part %d piece %.0f" % [b.seed, pi, c.r])
			if cut:
				cut_parts += 1
				want += 1
				if int(ends.get(xf, 0)) != 11:
					wrong.append("seed %d part %d ends %d" % [b.seed, pi, int(ends.get(xf, 0))])
		if boxes.size() != plain.size() + 2 * want:
			wrong.append("seed %d: %d boxes, %d without corners, %d cut" % [b.seed, boxes.size(), plain.size(), want])
		for e: Array in plain:
			if (e[2] as Color).r > 0.5 and is_equal_approx((e[2] as Color).a, FarBuilding.PART_FLAG):
				off_extra += 1
		b.free()
	_t._check(cut_parts > 20 and wrong.is_empty() and off_extra == 0,
		"a cut part's far box is its middle piece in its own place plus two end pieces, none with FAR_CORNERS off (%d cut parts%s)" % [cut_parts, (": " + ", ".join(wrong.slice(0, 4))) if wrong else ""])


## The three pieces, reshaped as the shader reshapes them, tile the near part's octagon exactly:
## their roofs' areas add up to the near footprint's, every corner lies on it, and each cut face's
## normal points out of the corner it cuts.
func _pieces_make_the_near_prism() -> void:
	var worst := 0.0
	var bad_normals := 0
	var cases := 0
	for s: Vector3 in [Vector3(40.0, 90.0, 32.0), Vector3(18.0, 30.0, 26.0), Vector3(61.3, 140.0, 44.7)]:
		for cols: Vector2i in [Vector2i(10, 8), Vector2i(6, 6), Vector2i(13, 9)]:
			var near := Building._footprint_polygon(s, s.x / cols.x, s.z / cols.y)
			var area := 0.0
			for piece: float in [FarBuilding.PIECE_MIDDLE, FarBuilding.PIECE_PLUS_X, FarBuilding.PIECE_MINUS_X]:
				# The box's top face, corners in winding order, through the reshape.
				var top := PackedVector2Array()
				for c: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
					var v := _reshape(Vector3(c.x, 0.5, c.y), Vector3.UP, piece, cols, s)[0] as Vector3
					var m := Vector2(v.x * s.x, v.z * s.z)
					top.append(m)
					worst = maxf(worst, _off_polygon(m, near))
				area += absf(_area(top))
				if piece > 1.5:
					for nz: float in [1.0, -1.0]:
						var n: Vector3 = _reshape(Vector3(0.5, 0.5, 0.5 * nz), Vector3(0.0, 0.0, nz), piece, cols, s)[1]
						var corner := Vector2(1.0 if piece < 2.5 else -1.0, nz)
						if Vector2(n.x, n.z).dot(corner) <= 0.5 * corner.length() or absf(n.y) > 1e-5:
							bad_normals += 1
			worst = maxf(worst, absf(area - absf(_area(near))))
			cases += 1
	_t._check(worst < 0.01 and bad_normals == 0,
		"the far pieces tile the near part's cut footprint (%d cases, worst %.4f m / m2, %d bad cut normals)" % [cases, worst, bad_normals])


## The shader still reads the piece from INSTANCE_CUSTOM.r and the bays from the code's cols word.
func _shader_has_the_reshape() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var ok := src.contains("INSTANCE_CUSTOM.a < -0.5 && INSTANCE_CUSTOM.r > 0.5") \
		and src.contains("uint cd = uint(round(MODEL_MATRIX[1][2] * 268435456.0) + 0.5);") \
		and src.contains("VERTEX.x = sx * (0.5 - cxu);") and src.contains("VERTEX.z = sz * (0.5 - czu);")
	_t._check(ok, "building_lod.gdshader carries the cut-corner reshape the checks mirror")


## The LOD build (and so the far city's capture) emits two end pieces for every middle piece.
func _captured_blocks_keep_the_pieces(city: Node3D) -> void:
	var streamer := city as CityStreamer
	if streamer == null or not FarBuilding.enabled or not FarBuilding.corners:
		_t._check(FarBuilding.enabled and FarBuilding.corners, "the far boxes are coded with cut corners")
		return
	var plan: CityPlan = streamer.plan
	var middles := 0
	var ends := 0
	for k: Vector2i in [Vector2i(7, 2), Vector2i(3, -3), Vector2i(10, 5), Vector2i(5, -2), Vector2i(-3, 6), Vector2i(8, 0)]:
		var b := plan.block(k.x, k.y)
		if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			continue
		var cap := CityChunk.new()
		cap.plan = plan
		cap.ix = k.x
		cap.iz = k.y
		cap.level = CityChunk.Level.LOD
		cap.style = streamer.chunk_style()
		cap.capturing = true
		cap.build()
		var lb: Dictionary = cap.captured.batch.get("lod_box", {"custom": []})
		for c: Color in lb.custom:
			if is_equal_approx(c.a, FarBuilding.PART_FLAG):
				if is_equal_approx(c.r, FarBuilding.PIECE_MIDDLE):
					middles += 1
				elif c.r > 1.5:
					ends += 1
		cap.free()
	_t._check(middles > 0 and ends == 2 * middles,
		"the far city captures every cut part as three pieces (%d cut parts, %d end pieces)" % [middles, ends])


## building_lod.gdshader's reshape of a coded piece's unit-box vertex `v` (normal `n`): [v, n].
func _reshape(v: Vector3, n: Vector3, piece: float, cols: Vector2i, bs: Vector3) -> Array:
	var cxu := 1.0 / maxf(float(cols.x), 1.0)
	var czu := 1.0 / maxf(float(cols.y), 1.0)
	var sx := 1.0 if v.x > 0.0 else -1.0
	if piece < 1.5:
		v.x = sx * (0.5 - cxu)
	else:
		var end := 1.0 if piece < 2.5 else -1.0
		var sz := 1.0 if v.z > 0.0 else -1.0
		if sx != end:
			v.x = end * (0.5 - cxu)
		else:
			v.z = sz * (0.5 - czu)
		if absf(n.z) > 0.5:
			n = Vector3(end * czu * bs.z, 0.0, signf(n.z) * cxu * bs.x).normalized()
	return [v, n]


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


## How far `q` lies outside the convex polygon `poly` (0 inside or on it).
static func _off_polygon(q: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(q, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(c))
	return best
