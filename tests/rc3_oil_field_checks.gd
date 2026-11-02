extends RefCounted
## The oil field refcam (fleet wave 6, rc3-oil-field; docs/HANDOFF.md "The oil field from its lease
## road"): checks for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * the camera row is in tools/refcams/cameras_w6.json on the crest lease road;
##   * OilFieldPlanting's keep-outs are pure and right: nothing on a lease road, a pad or the fence;
##     the shells' COLOR.b is under 0.5 on a road and over it out on the hill;
##   * the FULL chunk under the eye plants shrubs, clumps and the hill shells on the field's ground,
##     none of it in a keep-out, and parks its service pickups on pads;
##   * the dirt's edge crumbles in world space (oil_dirt.gdshader `crumble_edge`).
## OIL_PLANTING=0 is the A/B: nothing is planted and the checks only say so.

var _t: Node

## The refcam's eye (tools/refcams/cameras_w6.json, oil_field): on the crest loop.
const EYE := Vector2(611.4, 1542.8)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	if not OilFieldPlanting.enabled or not OilField.enabled:
		_t._check(true, "rc3-oil-field: off (OIL_PLANTING=0 or OIL_FIELD=0)")
		return
	var plan: CityPlan = city.get("plan") if city else null
	if plan == null or plan.macro == null or plan.macro.oil == null:
		_t._check(true, "rc3-oil-field: no oil field on this seed")
		return
	var f: OilField = plan.macro.oil
	_keep_outs(f)
	_shader()
	_chunk(city, plan, f)


func _camera_row() -> void:
	var src := FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json")
	var data: Variant = JSON.parse_string(src)
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "oil_field":
				found = absf(float(c.eye[0]) - EYE.x) < 0.01 and absf(float(c.eye[2]) - EYE.y) < 0.01 and float(c.hour) == 16.0
	_t._check(found, "rc3-oil-field: the oil_field row is in cameras_w6.json on the crest road at 16:00")


func _keep_outs(f: OilField) -> void:
	# On a lease road's centre line: no room, and the shells keep off it.
	var rd: Dictionary = f.roads[0]
	var p0: Vector2 = (rd.pts as PackedVector2Array)[(rd.pts as PackedVector2Array).size() / 2]
	_t._check(not OilFieldPlanting.room(f, p0, 0.0) and OilFieldPlanting.shell_keep(f, p0) < 0.5,
		"rc3-oil-field: a lease road keeps the planting and the shells off it")
	var pd: Dictionary = f.pads[0]
	_t._check(not OilFieldPlanting.room(f, pd.c, 0.0) and OilFieldPlanting.shell_keep(f, pd.c) < 0.5,
		"rc3-oil-field: a pad keeps the planting and the shells off it")
	# Out on the hill some points are open (the shells grow there), and it is pure.
	var open := 0
	var n := 0
	var same := true
	for i in 30:
		for j in 30:
			var p := f.rect.position + f.rect.size * Vector2((i + 0.5) / 30.0, (j + 0.5) / 30.0)
			n += 1
			if OilFieldPlanting.shell_keep(f, p) > 0.5:
				open += 1
			same = same and is_equal_approx(OilFieldPlanting.stand(f, p), OilFieldPlanting.stand(f, p))
	_t._check(same and open > n / 3 and open < n, "rc3-oil-field: the shells grow over %d of %d points of the field, pure" % [open, n])


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/oil_dirt.gdshader")
	var mat := OilFieldBuild.dirt_material()
	_t._check(src.contains("crumble_edge") and bool(mat.get_shader_parameter("crumble_edge")),
		"rc3-oil-field: the dirt's edge crumbles in world space, not a screen dither")


func _chunk(city: Node3D, plan: CityPlan, f: OilField) -> void:
	var k := plan.block_index_at(EYE)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var done: Dictionary = chunk.get_meta("oil_planting_done", {})
	_t._check(int(done.get("shrub", 0)) > 40 and int(done.get("clump", 0)) > 20,
		"rc3-oil-field: the eye's chunk plants shrubs and clumps (%d shrubs, %d sage, %d clumps, %d oaks)" % [
			int(done.get("shrub", 0)), int(done.get("sage", 0)), int(done.get("clump", 0)), int(done.get("oak", 0))])
	var bad := 0
	var trucks := 0
	for e: Array in done.get("points", []):
		var p: Vector2 = e[0]
		if String(e[1]) == "truck":
			trucks += 1
			# On a pad, not a road.
			var on_pad := false
			for pd: Dictionary in f.pads:
				on_pad = on_pad or OilField.pad_dist(pd, p) < 0.0
			if not on_pad:
				bad += 1
		elif not OilFieldPlanting.room(f, p, 0.0):
			bad += 1
	_t._check(bad == 0, "rc3-oil-field: nothing planted on a road, a pad or the fence, and every pickup on a pad (%d wrong)" % bad)
	_t._check(trucks == int(done.get("truck", 0)), "rc3-oil-field: %d service pickups parked" % trucks)
	if CityChunk.shells_enabled:
		_t._check(chunk.find_child("HillShells", false, false) != null, "rc3-oil-field: the field's ground grows the hill shells")
	chunk.queue_free()
