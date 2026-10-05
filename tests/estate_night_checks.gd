extends RefCounted
## The hillside estates past the FULL chunks (EstateFar, shaders/far_estate.gdshader), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The parts are pure and whole: the same estate gives the same parts; a pad, a house with its
## roof, a pool where CityChunk's FULL estate puts it, lamps (gate, door, garden); everything but a
## driveway's lamps inside the pad; every code survives the half floats the Compatibility renderer
## hands INSTANCE_CUSTOM over as. The shader's copy of the far plane's height is far_canopy's. A
## LOD hill chunk lays its estates as the one batch on that material (no pale pavers pad, no
## lod_box house), and a far-city tile lays them on it with their trees in the planting.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	_t._check(EstateFar.enabled, "the far estates are on (ESTATE_NIGHT is not 0)")
	if macro == null or macro.hill_roads == null or macro.hill_roads.mansions.is_empty():
		_t._check(false, "the plan has hill estates to check")
		return
	# An estate a hill chunk builds (one whose block is not a hill block is never built).
	var m: Dictionary = {}
	for e: Dictionary in macro.hill_roads.mansions:
		var k := plan.block_index_at(e.pos)
		if plan.zone_at((plan.block(k.x, k.y).rect as Rect2).get_center()) == MacroMap.Zone.HILLS:
			m = e
			break
	_t._check(not m.is_empty(), "a hill chunk builds an estate to check")
	if m.is_empty():
		return
	_parts(plan, macro)
	_shader()
	_lod_chunk(city, plan, m)
	_far_tile(city, plan, macro, m)


## Half-float rounding (11 significant bits), as Compatibility stores INSTANCE_CUSTOM.
static func _half(v: float) -> float:
	if v == 0.0:
		return 0.0
	var e := floorf(log(absf(v)) / log(2.0))
	var q := pow(2.0, e - 10.0)
	return roundf(v / q) * q


func _parts(plan: CityPlan, macro: MacroMap) -> void:
	var same := true
	var whole := true
	var inside := true
	var codes := true
	var pool_ok := true
	var lamps_min := 1000
	var n := 0
	for m: Dictionary in macro.hill_roads.mansions.slice(0, 60):
		var a := EstateFar.parts(m, false, plan.height_at)
		var b := EstateFar.parts(m, false, plan.height_at)
		same = same and str(a) == str(b)
		var kinds := {}
		var lamps := 0
		var basis := Basis(Vector3.UP, float(m.yaw))
		var centre := Vector3((m.pos as Vector2).x, float(m.height) + EstateFar.PAD.y, (m.pos as Vector2).y)
		for p: Array in a:
			var c: Color = p[2]
			var code := c.g
			var kind := int(floor(code + 0.002))
			kinds[kind] = kinds.get(kind, 0) + 1
			# Survives half floats: the kind and the offsets to the estate's centre.
			var hk := int(floor(_half(code) + 0.002))
			codes = codes and hk == kind and absf(_half(c.b) - c.b) < 0.02 and absf(_half(c.a) - c.a) < 0.02 and absf(_half(c.r) - c.r) < 0.02
			var xf: Transform3D = p[0]
			var local := basis.inverse() * (xf.origin - centre)
			if kind == EstateFar.K_LAMP:
				lamps += 1
				# The driveway lamps stand off the pad; the rest on it.
				continue
			inside = inside and absf(local.x) <= EstateFar.PAD.x * 0.5 + 0.5 and absf(local.z) <= EstateFar.PAD.z * 0.5 + 0.5
		whole = whole and kinds.get(EstateFar.K_PAD, 0) == 1 and kinds.get(EstateFar.K_HOUSE, 0) >= 1 \
			and kinds.get(EstateFar.K_ROOF, 0) == kinds.get(EstateFar.K_HOUSE, 0) and kinds.get(EstateFar.K_POOL, 0) == 1
		lamps_min = mini(lamps_min, lamps)
		# The pool where CityChunk._build_mansions puts it: its first two rolls on the seed.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(m.seed)
		var px := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(5.0, 6.5)
		for p: Array in a:
			if int(floor((p[2] as Color).g + 0.002)) == EstateFar.K_POOL:
				var local := basis.inverse() * ((p[0] as Transform3D).origin - centre)
				pool_ok = pool_ok and absf(local.x - px) < 0.01 and absf(local.z - 6.0) < 0.01
		n += 1
	_t._check(same, "an estate's far parts are the same every time (%d estates)" % n)
	_t._check(whole, "every far estate has one pad, a house under a roof and one pool")
	_t._check(lamps_min >= 7, "every far estate has its lamps: gate, door and garden (fewest %d)" % lamps_min)
	_t._check(inside, "every far estate's parts but its driveway lamps stand on its pad")
	_t._check(pool_ok, "the far pool is where the FULL estate builds it")
	_t._check(codes, "the far estates' codes survive half floats (kind, deck height, offsets)")
	var real := EstateFar.parts(macro.hill_roads.mansions[0], true, plan.height_at)
	_t._check(int(floor((real[0][2] as Color).g + 0.002)) == EstateFar.K_PAD + EstateFar.REAL, "a LOD chunk's parts are flagged to stay on the real terrain")


## The shader's plane_height() and corner_height() are far_canopy.gdshader's, character for character.
func _shader() -> void:
	var mine := FileAccess.get_file_as_string("res://shaders/far_estate.gdshader")
	var theirs := FileAccess.get_file_as_string("res://shaders/far_canopy.gdshader")
	var ok := true
	for fn in ["float corner_height(", "float plane_height("]:
		ok = ok and _body(mine, fn) != "" and _body(mine, fn) == _body(theirs, fn)
	_t._check(ok, "far_estate.gdshader seats on the far plane exactly as far_canopy.gdshader does")


static func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\n}\n", i)
	return src.substr(i, j - i)


func _lod_chunk(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var k := plan.block_index_at(m.pos)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var batch := chunk.get_node_or_null("Batch_estate_far") as MultiMeshInstance3D
	var count := 0
	for e in plan.macro.hill_roads.mansions_in(chunk.owned_rect()):
		count += EstateFar.parts(e, true, plan.height_at).size()
	var ok := batch != null and batch.multimesh.instance_count == count and (batch.multimesh.mesh as Mesh).surface_get_material(0) == EstateFar.material() \
		and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_t._check(ok, "a LOD hill chunk lays its estates as one shadowless far-estate batch (%d parts)" % (batch.multimesh.instance_count if batch else -1))
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _far_tile(city: Node3D, plan: CityPlan, macro: MacroMap, m: Dictionary) -> void:
	var sky := Skyline.new()
	var canopy := ShaderMaterial.new()
	sky.setup(plan, city.chunk_style(), canopy)
	var k := plan.block_index_at(m.pos)
	var t := Skyline.tile_of(k)
	sky._work = {"t": t, "xforms": [], "colors": [], "customs": [], "veg": [], "veg_colors": [], "veg_custom": [],
		"houses": [], "house_colors": [], "house_custom": [], "hills": {}, "ranges": {}}
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var veg_before := 0
	sky._add_hills(rect, macro)
	var expected := 0
	var trees := 0
	for e in macro.hill_roads.mansions_in(rect):
		expected += EstateFar.parts(e, false, macro.height_at).size()
		trees += EstateFar.trees(e).size()
	var houses: Array = sky._work.houses
	_t._check(houses.size() == expected and (sky._work.house_custom as Array).size() == expected and (sky._work.veg as Array).size() - veg_before >= trees,
		"a far-city hill block lays its estates' parts (%d of %d) and their trees" % [houses.size(), expected])
	sky._commit_tile()
	var tile = sky._tiles.get(t)
	var node: MultiMeshInstance3D = tile.house if tile else null
	_t._check(node != null and node.material_override == EstateFar.material(), "the far city's estates wear the far-estate material")
	sky.free()
