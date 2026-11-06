extends RefCounted
## The film lot refcam (fleet wave 7, rc4-film-lot; docs/HANDOFF.md "The film lot at 14:00"):
## checks for tests/smoke_test.gd. CPU only (no pixel is read headless):
##   * the film_lot row is in tools/refcams/cameras_w7.json, inside the lot at 14:00;
##   * Rc4FilmLot.dressing() is pure, puts golf carts in the basecamp's gaps, and nothing it plans
##     stands in a stage or on a trailer;
##   * a FULL studio chunk on the street lays its asphalt KEPT (industrial_ground `kept`) and its
##     trailers, trucks and carts as batched variants; the industrial district's own stays failed;
##   * the cached variants stay under a triangle budget.
## RC4_FILM_LOT=0 is the A/B: the old kit and the industrial ground.

var _t: Node

const EYE := Vector2(640.0, -470.0)
## Triangles one trailer / truck variant may hold.
const VARIANT_BUDGET := 6000


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	var plan: CityPlan = city.get("plan") if city else null
	var lay := FilmStudio.layout(plan) if plan else {}
	if lay.is_empty():
		_t._check(true, "rc4-film-lot: no studio on this plan (FILM_STUDIO=0)")
		return
	_t._check((lay.inner as Rect2).has_point(EYE), "rc4-film-lot: the camera stands inside the studio wall")
	if not Rc4FilmLot.enabled:
		_t._check(true, "rc4-film-lot: off (RC4_FILM_LOT=0)")
		return
	_dressing(plan, lay)
	_variants()
	_full_chunk(city, plan)


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "film_lot":
				found = absf(float(c.eye[0]) - EYE.x) < 0.01 and absf(float(c.eye[2]) - EYE.y) < 0.01 \
					and absf(float(c.hour) - 14.0) < 0.01 and String(c.get("weather", "")) == "clear"
	_t._check(found, "rc4-film-lot: the film_lot row is in cameras_w7.json at 14:00 clear")


func _dressing(plan: CityPlan, lay: Dictionary) -> void:
	var a := Rc4FilmLot.dressing(lay, plan.seed)
	var b := Rc4FilmLot.dressing(lay, plan.seed)
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and (a[i].at as Vector2).is_equal_approx(b[i].at) and String(a[i].kind) == String(b[i].kind)
	_t._check(same and a.size() > 0, "rc4-film-lot: the basecamp's dressing plans the same twice (%d pieces)" % a.size())
	var carts := 0
	var bad: Array[String] = []
	for d: Dictionary in a:
		var p: Vector2 = d.at
		if String(d.kind) == "cart":
			carts += 1
		if String(d.kind) == "ramp":
			continue
		for sg: Dictionary in lay.stages:
			var sz: Vector3 = sg.size
			var ext := Vector2(sz.x, sz.z) if is_zero_approx(float(sg.yaw)) else Vector2(sz.z, sz.x)
			if Rect2((sg.c as Vector2) - ext * 0.5, ext).has_point(p):
				bad.append("%s in stage %d" % [d.kind, int(sg.number)])
		for pk: Dictionary in lay.parking:
			var l: float = float(pk.length) - 1.6
			var yaw: float = pk.yaw
			var local := (p - (pk.at as Vector2)).rotated(yaw)
			if absf(local.x) < 1.2 and absf(local.y) < l * 0.5:
				bad.append("%s on a %s at %s" % [d.kind, pk.kind, p])
		if not (lay.inner as Rect2).has_point(p):
			bad.append("%s outside the wall at %s" % [d.kind, p])
	_t._check(carts >= 3, "rc4-film-lot: golf carts park in the basecamp's gaps (%d)" % carts)
	_t._check(bad.is_empty(), "rc4-film-lot: no dressing in a stage, on a trailer or outside the wall %s" % [bad.slice(0, 4)])


func _variants() -> void:
	var tr := Rc4FilmLot.cached("rc4_check_trailer", func(st: SurfaceTool) -> void: Rc4FilmLot.trailer(st, Transform3D.IDENTITY, 10.4, false, 1, 3))
	var tk := Rc4FilmLot.cached("rc4_check_truck", func(st: SurfaceTool) -> void: Rc4FilmLot.truck(st, Transform3D.IDENTITY, 1, 1))
	var t1 := CityChunk._mesh_tris(tr)
	var t2 := CityChunk._mesh_tris(tk)
	var ok := tr.get_surface_count() == 1 and tk.get_surface_count() == 1 and tr.surface_get_material(0) == FilmStudioKit.material()
	_t._check(ok and t1 > 400 and t1 < VARIANT_BUDGET and t2 > 300 and t2 < VARIANT_BUDGET,
		"rc4-film-lot: a trailer (%d tris) and a truck (%d) are one surface on the studio material, under %d" % [t1, t2, VARIANT_BUDGET])
	var s := Rc4FilmLot.section(1.0, 0.0, 2.0, 0.1, 0.3, 4)
	var pts: PackedVector2Array = s[0]
	var nrm: PackedVector2Array = s[1]
	var outward := true
	for i in pts.size():
		outward = outward and nrm[i].dot(pts[i] - Vector2(0.0, 1.0)) > 0.0
	_t._check(outward and pts[0].is_equal_approx(pts[pts.size() - 1]), "rc4-film-lot: the rounded section is closed and its normals face out")


func _full_chunk(city: Node3D, plan: CityPlan) -> void:
	var k0: Vector2i = plan.block_index_at(Vector2(EYE.x - 30.0, EYE.y))
	var road_ok := false
	var trailers := 0
	var carts := 0
	for k: Vector2i in [k0, k0 + Vector2i(1, 0)]:
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var ground: MeshInstance3D = chunk.get_node_or_null("StudioGround")
		if ground != null and ground.material_override is ShaderMaterial and (ground.material_override as ShaderMaterial).get_shader_parameter("kept") != null \
				and float((ground.material_override as ShaderMaterial).get_shader_parameter("kept")) > 0.5:
			road_ok = true
		for c in chunk.get_children():
			if c is MultiMeshInstance3D:
				var n := String(c.name)
				if n.begins_with("Batch_rc4_trailer") or n.begins_with("Batch_rc4_truck"):
					trailers += (c as MultiMeshInstance3D).multimesh.instance_count
				elif n.begins_with("Batch_rc4_cart"):
					carts += (c as MultiMeshInstance3D).multimesh.instance_count
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	var ik: Variant = Industrial.ground_material().get_shader_parameter("kept")
	_t._check(ik == null or float(ik) < 0.5, "rc4-film-lot: the industrial yards' own ground keeps its failed asphalt")
	_t._check(road_ok, "rc4-film-lot: the studio ground wears the kept asphalt (industrial_ground kept 1)")
	_t._check(trailers >= 2 and carts >= 1, "rc4-film-lot: the street's chunks batch their trailers and trucks (%d) and carts (%d)" % [trailers, carts])
