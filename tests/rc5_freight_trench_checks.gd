extends RefCounted
## The freight trench refcam (RcFreightTrench; camera `freight_trench` in tools/refcams/cameras_w8.json),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the trench wears its own copy of the structure material with the trench look on (the
## freeway's own untouched); the shaders carry the passes off by default; the track material turns
## the mainline ballast pass on; a deep trench stretch lays the wall conduit and its pull box, a
## shallow one none; the ballast's crib sits between the ties' top and bottom; the camera row stages
## a northbound train with its nose where the row says; RC5_FREIGHT_TRENCH=0 puts the old back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was: bool = RcFreightTrench.enabled
	RcFreightTrench.enabled = true
	_materials()
	_shaders()
	_stretch(city)
	_camera(city)
	RcFreightTrench.enabled = false
	_t._check(RcFreightTrench.structure_material() == FreewayKit.structure_material(), "RC5_FREIGHT_TRENCH=0: the trench wears the freeway's structure material")
	_t._check(is_equal_approx(RcFreightTrench.ballast_drop(FreightKit.BALLAST_DROP), FreightKit.BALLAST_DROP), "RC5_FREIGHT_TRENCH=0: the ballast's old drop")
	RcFreightTrench.enabled = was


func _materials() -> void:
	var m := RcFreightTrench.structure_material()
	_t._check(m != FreewayKit.structure_material(), "the trench has its own copy of the structure material")
	_t._check(float(m.get_shader_parameter("trench_look")) == 1.0, "the trench's material has the trench look on")
	var fw: Variant = FreewayKit.structure_material().get_shader_parameter("trench_look")
	_t._check(fw == null or float(fw) == 0.0, "the freeway's own structure material keeps the trench look off")
	_t._check(m.get_shader_parameter("tag_atlas") != null, "the trench's walls have the tag atlas for their graffiti")
	_t._check(float(FreightKit.track_material().get_shader_parameter("rc5")) == 1.0, "the track material turns the mainline ballast pass on")
	var drop := RcFreightTrench.ballast_drop(FreightKit.BALLAST_DROP)
	# The concrete tie's top is 0.172 under the rail top, 0.21 deep.
	_t._check(drop > 0.172 + 0.02 and drop < 0.172 + 0.21 - 0.08, "the crib's ballast lies between the ties' top and bottom (%.3f under the rail)" % drop)


func _shaders() -> void:
	var st := FileAccess.get_file_as_string("res://shaders/freeway_structure.gdshader")
	_t._check(st.contains("uniform float trench_look = 0.0;"), "freeway_structure.gdshader: the trench look is off by default")
	_t._check(st.contains("if (trench_look > 0.5 && UV2.y > 3.0)"), "freeway_structure.gdshader: the trench look only on wall-height faces")
	var tr := FileAccess.get_file_as_string("res://shaders/freight_track.gdshader")
	_t._check(tr.contains("uniform float rc5 = 0.0;"), "freight_track.gdshader: the mainline ballast pass is off by default")
	_t._check(tr.contains("rc5 > 0.5 && UV2.y > 0.95"), "freight_track.gdshader: the pass only on the mainline's beds (the yard's stay)")


func _count(st: SurfaceTool) -> int:
	var m := st.commit()
	return m.surface_get_array_len(0) if m.get_surface_count() > 0 else 0


func _stretch(city: Node3D) -> void:
	var plan: CityPlan = city.get("plan")
	var line := FreightRail.of(plan)
	if line == null:
		_t._check(false, "the freight line resolves for the trench checks")
		return
	# A deep stretch (rail 9.4 m under the street) between two decks, where a wall light hangs
	# ((s + 8) mod WALL_LIGHT_EVERY < SEG).
	var s := 1400.0
	var key := plan.chunk_index_at(Vector2(line.avenue_x, line.z0 + s))
	var c: CityChunk = city.call("_new_chunk", key, CityChunk.Level.FULL)
	var counts: Array[int] = []
	for on: bool in [false, true]:
		RcFreightTrench.enabled = on
		var kit := FreightKit.new(c)
		kit.fr = line
		kit.area = c.owned_rect()
		kit.full = true
		kit._trench(s, s + FreightKit.SEG)
		counts.append(_count(kit.body))
	RcFreightTrench.enabled = true
	_t._check(counts[1] > counts[0] + 100, "a deep trench stretch lays the wall conduit, its straps and a pull box (%d -> %d vertices)" % [counts[0], counts[1]])
	# The ramps' shallow ends get no conduit (it would stand over the parapet).
	var shallow := line.s_grade0 - 30.0
	var sc: Array[int] = []
	for on: bool in [false, true]:
		RcFreightTrench.enabled = on
		var kit := FreightKit.new(c)
		kit.fr = line
		kit.area = c.owned_rect()
		kit.full = true
		kit._trench(shallow, shallow + FreightKit.SEG)
		sc.append(_count(kit.body))
	RcFreightTrench.enabled = true
	_t._check(sc[0] == sc[1], "a shallow stretch by the ramp lays no conduit (%d, %d vertices)" % [sc[0], sc[1]])
	if c.get_parent():
		c.get_parent().remove_child(c)
	c.free()


func _camera(city: Node3D) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for r: Dictionary in data.get("cameras", []):
			if String(r.get("name", "")) == "freight_trench":
				row = r
	_t._check(not row.is_empty() and row.has("freight_s"), "cameras_w8.json has the freight_trench row with its freight_s staging")
	if row.is_empty():
		return
	var line := FreightRail.of(city.get("plan"))
	if line == null:
		return
	var fs := String(row.freight_s).split(":", false)
	var want := fs[0].to_float()
	var kind := int(row.get("freight_kind", -1))
	var clock := line.clock_at_s(want, 0, 0.0, 5400.0)
	var n := line.trip_near(5400.0, kind)
	var hit := false
	for st: Dictionary in line.trains_at(clock):
		if int(st.n) == line.trip_near(5400.0) and absf(float(st.sA) - want) < 2.0:
			hit = true
	_t._check(hit, "the freight_trench row's clock puts a northbound train's nose at s %.0f" % want)
	_t._check(kind < 0 or int(line.consist(n).kind) == kind, "a trip of the row's consist kind is found near the clock")
