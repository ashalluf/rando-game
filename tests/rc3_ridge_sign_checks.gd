extends RefCounted
## The ridge-sign reference camera (fleet wave 6, rc3-ridge-sign; docs/HANDOFF.md "The ridge sign
## refcam"): checks for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * the letters are one mesh of ribbons on the sheet-metal shader, across the old span, with no
##     two front faces of one letter in the same plane (no z-fighting);
##   * the shrub gathering field is pure, has gaps and scales what it keeps;
##   * the bake paints a HILLS block's flat foot as hill ground, never as a city district;
##   * the camera row is in cameras_w6.json.
## RC3_SIGN=0 is the A/B: everything goes back, and the checks only say so.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not RcRidgeSign.on():
		_t._check(true, "rc3-ridge-sign: off (RC3_SIGN=0)")
		return
	var plan: CityPlan = city.get("plan") if city else null
	if plan and plan.macro:
		_letters(plan)
		_bake_zone(plan)
	_shrubs()
	_camera()
	_shader()


func _letters(plan: CityPlan) -> void:
	var lm: Dictionary = {}
	for l: Dictionary in Landmarks.all():
		if l.id == "sign":
			lm = l
	if lm.is_empty():
		_t._check(false, "rc3-ridge-sign: the sign landmark exists")
		return
	var holder := Node3D.new()
	HillSignLetters.build(lm.anchor, holder, null, plan, false)
	var letters := holder.get_node_or_null("SignLetters") as MeshInstance3D
	var ok := letters != null and letters.mesh != null and letters.mesh.get_surface_count() == 1
	var mat_ok := ok and letters.material_override is ShaderMaterial \
		and String((letters.material_override as ShaderMaterial).shader.resource_path).ends_with("ridge_sign.gdshader")
	_t._check(mat_ok, "rc3-ridge-sign: the letters are one mesh on the sheet-metal shader")
	if not ok:
		holder.free()
		return
	var span := letters.mesh.get_aabb().size.x
	_t._check(absf(span - Landmarks.SIGN_SPAN) < Landmarks.SIGN_SPAN * 0.05, "rc3-ridge-sign: the ribbons span the old sign (%.0f m)" % span)
	# Front faces (COLOR.a 1): per letter (UV2.x), the depths they sit at. Strokes of a letter that
	# overlap must not share a plane: every stroke's front is its own depth.
	var arrays: Array = HillSignLetters.last_arrays
	if arrays.is_empty():
		_t._check(false, "rc3-ridge-sign: the letters' arrays were kept")
		holder.free()
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var fronts := 0
	var wound := 0
	var depths := {}
	for i in range(0, verts.size(), 3):
		if cols[i].a < 0.9:
			continue
		fronts += 1
		var li := int(uv2[i].x)
		if not depths.has(li):
			depths[li] = {}
		(depths[li] as Dictionary)[snappedf(verts[i].z, 0.001)] = true
		# Clockwise seen from the front: the edges' cross product points away from the normal.
		if (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).dot(normals[i]) <= 0.0:
			wound += 1
	_t._check(fronts > 0 and wound == fronts, "rc3-ridge-sign: every front triangle faces out (%d of %d)" % [wound, fronts])
	var multi := 0
	for li in depths:
		if (depths[li] as Dictionary).size() > 1:
			multi += 1
	_t._check(multi >= 8, "rc3-ridge-sign: a letter's strokes stand at their own depths (%d letters with several)" % multi)
	holder.free()


func _bake_zone(plan: CityPlan) -> void:
	# The four blocks at the foot of the sign (seed 1337): HILLS by their centre, city ground in their
	# south half. The bake's callable must call that half HILLS.
	var fn := RcRidgeSign.block_zone_fn(plan)
	var p := Vector2(546.0, -853.0)
	var own := int(plan.zone_at(p))
	var blk := int(fn.call(p))
	var bi: Vector2i = plan.block_index_at(p)
	var centre := int(plan.zone_at((plan.block(bi.x, bi.y).rect as Rect2).get_center()))
	_t._check(blk == centre, "rc3-ridge-sign: the bake's block zone is the chunk's (point %d, block %d, chunk %d)" % [own, blk, centre])


func _shrubs() -> void:
	var gaps := 0
	var kept := 0
	var lo := INF
	var hi := -INF
	for i in 400:
		var p := Vector2(float(i % 20) * 7.3 - 40.0, float(i / 20) * 7.3 + 1200.0)
		var a := RcRidgeSign.shrub_gather(p, 0.5)
		if a != RcRidgeSign.shrub_gather(p, 0.5):
			_t._check(false, "rc3-ridge-sign: the shrub field is pure")
			return
		if a <= 0.0:
			gaps += 1
		else:
			kept += 1
			lo = minf(lo, a)
			hi = maxf(hi, a)
	_t._check(gaps > 40 and kept > 120, "rc3-ridge-sign: shrubs gather into thickets with gaps (%d kept, %d gaps)" % [kept, gaps])
	_t._check(kept > 0 and hi - lo > 0.3, "rc3-ridge-sign: a thicket's shrubs are sized by the field (%.2f..%.2f)" % [lo, hi])


func _camera() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w6.json", FileAccess.READ)
	var found := false
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for c: Dictionary in d.get("cameras", []):
				if c.get("name", "") == "ridge_sign":
					found = float(c.hour) == 16.5 and c.weather == "clear"
	_t._check(found, "rc3-ridge-sign: the ridge_sign camera row (16:30, clear) is in cameras_w6.json")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/ridge_sign.gdshader")
	_t._check(src.contains("color_space.gdshaderinc") and src.contains("cs_out("), "rc3-ridge-sign: the letter shader works in linear (color_space)")
