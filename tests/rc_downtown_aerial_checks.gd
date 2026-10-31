extends RefCounted
## The downtown aerial refcam pass (docs/HANDOFF.md "The civic centre from the air", rc-downtown-
## aerial) for tests/smoke_test.gd:
## - CivicGrounds: city hall's block leaves two slabs either side of the hall, they are laid as
##   lawns inside the block and off every civic site, the far copy plants the same trees as the
##   detailed one, CIVIC_GROUNDS=0 builds nothing; downtown park lawns are watered, others not.
## - The weathered roofs: one include in both building shaders, its derivatives outside any
##   branch, the switch reaching a built Building's material and the far boxes' material.
## - The landmark facade's windows are coverage, not a hard test, with the footprint taken outside
##   the window branch.
## - The refcam points at the civic centre: city hall is in front of downtown_aerial's camera.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	_t._check(plan != null, "downtown aerial: the city has a plan")
	if plan == null:
		return
	_grounds(plan, city)
	_lawns(plan)
	_shaders()
	_materials(city)
	_camera()


func _grounds(plan: CityPlan, city: Node3D) -> void:
	var left := CivicGrounds.leftovers(plan, "ziggurat_hall")
	_t._check(left.size() >= 2, "downtown aerial: city hall's block leaves ground either side of the hall (%d rects)" % left.size())
	var block := Landmarks.site_rect(plan, CivicSites.anchor("ziggurat_hall"))
	var bad := ""
	for r in left:
		if not block.grow(0.01).encloses(r):
			bad += " outside block %s" % r
		for id: String in CivicGrounds.CIVIC:
			var site: Rect2 = CivicSites.site(plan, id).world
			if site.grow(-0.1).intersects(r.grow(-0.1)):
				bad += " on %s %s" % [id, r]
	_t._check(bad == "", "downtown aerial: the civic grounds stay in the block and off every civic site%s" % bad)
	var lawns := CivicGrounds.lawn_rects(plan, "ziggurat_hall")
	_t._check(lawns.size() >= 8, "downtown aerial: city hall's grounds are lawns (%d quarters)" % lawns.size())
	_t._check(CivicGrounds.leftovers(plan, "civic_park").is_empty(), "downtown aerial: the park fills its own block (no leftovers)")
	# Built far and near off the tree: the same trees, the near one with benches.
	var counts := []
	for detailed: bool in [false, true]:
		var holder := Node3D.new()
		var info := CivicSites.site(plan, "ziggurat_hall")
		CivicGrounds.build(plan, "ziggurat_hall", info, holder, detailed)
		var trees := 0
		var benches := 0
		for mmi in holder.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			if String(mmi.name).contains("tree_"):
				trees += mm.instance_count
			elif String(mmi.name).contains("cg_bench"):
				benches += mm.instance_count
		counts.append([trees, benches])
		_t._check(holder.get_node_or_null("CivicGrounds_ziggurat_hall") != null, "downtown aerial: CivicGrounds builds city hall's grounds (%s)" % ("near" if detailed else "far"))
		holder.free()
	_t._check(counts[0][0] >= 16 and counts[0][0] == counts[1][0],
		"downtown aerial: the far copy plants the same trees as the near one (%d / %d)" % [counts[0][0], counts[1][0]])
	_t._check(counts[0][1] == 0 and counts[1][1] > 0, "downtown aerial: benches only up close (%d / %d)" % [counts[0][1], counts[1][1]])
	var was := CivicGrounds.enabled
	CivicGrounds.enabled = false
	var off := Node3D.new()
	CivicGrounds.build(plan, "ziggurat_hall", CivicSites.site(plan, "ziggurat_hall"), off, true)
	_t._check(off.get_child_count() == 0, "downtown aerial: CIVIC_GROUNDS=0 builds nothing")
	off.free()
	CivicGrounds.enabled = was


func _lawns(plan: CityPlan) -> void:
	var rolled := Color(1.05, 0.88, 0.55)
	var park := CivicSites.anchor("civic_park")
	var inside := CivicGrounds.park_lawn(Rect2(park + Vector2(200.0, 0.0), Vector2(90.0, 90.0)), rolled)
	_t._check(inside == CivicGrounds.LAWN_TINT, "downtown aerial: a downtown park's lawn is watered green")
	var far_away := CivicGrounds.park_lawn(Rect2(Vector2(-4000.0, -2500.0), Vector2(90.0, 90.0)), rolled)
	_t._check(far_away == rolled, "downtown aerial: a park outside downtown keeps its rolled lawn")


func _shaders() -> void:
	for p: String in ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		_t._check(src.contains("#include \"res://shaders/roof_weather.gdshaderinc\"") and src.contains("rw_membrane("),
			"downtown aerial: %s draws the weathered membrane" % p.get_file())
	var b := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var px_at := b.find("float roof_px = length(fwidth(local_pos.xz));")
	var roof_at := b.find("if (abs(n.y) > 0.5) {")
	_t._check(px_at > 0 and roof_at > px_at, "downtown aerial: the roof's pixel footprint is taken before the roof branch")
	var f := FileAccess.get_file_as_string("res://shaders/landmark_facade.gdshader")
	var fw := f.find("vec2 px = max(vec2(fwidth(uv.x), fwidth(wpos.y))")
	var win := f.find("if (wall && win_pitch.x > 0.0")
	_t._check(fw > 0 and win > fw and f.contains("float cov = cov2.x * cov2.y;"),
		"downtown aerial: landmark windows are antialiased coverage, footprint outside the branch")


func _materials(city: Node3D) -> void:
	var lod := PropFactory.building_lod_material()
	_t._check(lod.get_shader_parameter("roof_weather") == CivicGrounds.roof_weather, "downtown aerial: the far boxes take the roof switch")
	var found := false
	for node in city.find_children("Walls", "MeshInstance3D", true, false):
		if not (node.get_parent() is Building):
			continue
		var walls := node as MeshInstance3D
		var mat := walls.material_override as ShaderMaterial
		if mat == null and walls.mesh and walls.mesh.get_surface_count() > 0:
			mat = walls.mesh.surface_get_material(0) as ShaderMaterial
		if mat == null:
			continue
		found = true
		_t._check(mat.get_shader_parameter("roof_weather") == CivicGrounds.roof_weather, "downtown aerial: a built Building's material takes the roof switch")
		break
	_t._check(found, "downtown aerial: a built Building with a Walls material to read the roof switch off")


func _camera() -> void:
	var cams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras.json"))
	var cam: Dictionary = {}
	for c: Dictionary in cams.cameras:
		if c.name == "downtown_aerial":
			cam = c
	_t._check(not cam.is_empty(), "downtown aerial: the refcam is in cameras.json")
	if cam.is_empty():
		return
	var eye := Vector2(float(cam.eye[0]), float(cam.eye[2]))
	var yaw := deg_to_rad(float(cam.eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var to_hall := (CivicSites.anchor("ziggurat_hall") - eye).normalized()
	var off_axis := rad_to_deg(acos(clampf(fwd.dot(to_hall), -1.0, 1.0)))
	_t._check(off_axis < float(cam.fov) * 0.5, "downtown aerial: city hall is in front of the refcam (%.1f degrees off axis)" % off_axis)
