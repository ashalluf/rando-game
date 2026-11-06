extends RefCounted
## The arts_district refcam's fixes (wave 8, rc5-arts-district; RcArtsDistrict), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The switch reaches the walls material; the shader carries the brick branch (relief, the sash in
## its reveal) and the mural-on-brick branch, both off at the uniform's default; the Arts District
## still has brick warehouses with murals round the camera; a brick mural is flagged, a concrete one
## and every mural with the switch off keep the old 0.5; the door frame writes its jambs and header
## and nothing with the switch off; the camera row is there with its riders.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_t._check(false, "rc5_arts: the city has a plan")
		return
	_shader()
	_district(plan)
	_flag()
	_frame()
	_yard_car()
	_row()


func _shader() -> void:
	var walls := FileAccess.get_file_as_string("res://shaders/industrial_walls.gdshader")
	_t._check(walls.contains("uniform float rc5_arts = 0.0") and walls.count("rc5_arts > 0.5") >= 2,
		"RcArtsDistrict: industrial_walls carries the brick and mural branches, off by default")
	_t._check(walls.contains("texture(brick_nrm"), "RcArtsDistrict: the brick's normal map is read")
	var on := 1.0 if RcArtsDistrict.enabled else 0.0
	_t._check(is_equal_approx(float(IndustrialKit.walls_material().get_shader_parameter("rc5_arts")), on),
		"RcArtsDistrict: the walls material carries the switch")


func _district(plan: CityPlan) -> void:
	# The camera's warehouse: block (34, 2) east of Harbor Ave, brick, with murals.
	var brick := 0
	var murals := 0
	for bx in range(33, 36):
		for bz in range(0, 3):
			for e: Dictionary in Industrial.block_entries(plan, bx, bz):
				var lp: Dictionary = e.plan
				if lp.is_empty() or not bool(lp.get("arts", false)):
					continue
				if bool(lp.brick):
					brick += 1
					murals += (lp.murals as Array).size()
	_t._check(brick >= 2 and murals >= 2, "RcArtsDistrict: the Arts District round the camera has brick warehouses with murals (%d, %d murals)" % [brick, murals])


func _flag() -> void:
	var was := RcArtsDistrict.enabled
	RcArtsDistrict.enabled = true
	var on_brick := RcArtsDistrict.mural_flag(true)
	var on_concrete := RcArtsDistrict.mural_flag(false)
	RcArtsDistrict.enabled = false
	var off := RcArtsDistrict.mural_flag(true)
	RcArtsDistrict.enabled = was
	# The shader tells brick by COLOR.b > 0.75.
	_t._check(on_brick > 0.75 and on_concrete == 0.5 and off == 0.5,
		"RcArtsDistrict: a mural on brick is flagged, on concrete and with RC5_ARTS=0 it keeps 0.5")


func _frame() -> void:
	var was := RcArtsDistrict.enabled
	var counts := []
	for on in [true, false]:
		RcArtsDistrict.enabled = on
		var ch := CityChunk.new()
		Industrial._state(ch)
		var f := Industrial.frame(Rect2(0.0, 0.0, 40.0, 60.0), 0)
		var cx := {"ch": ch, "basis": Basis(), "f": f, "floor": 0.1}
		RcArtsDistrict.door_frame(cx, 10.0, 3.0, Industrial.GRADE_DOOR)
		var n := 0
		if ch._ind.walls != null:
			var arrays: Array = (ch._ind.walls as SurfaceTool).commit_to_arrays()
			n = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		counts.append(n)
		ch.free()
	RcArtsDistrict.enabled = was
	_t._check(int(counts[0]) >= 3 * 24 and int(counts[1]) == 0, "RcArtsDistrict: the door frame writes two jambs and a header, nothing when off (%d / %d vertices)" % counts)


func _yard_car() -> void:
	var was := RcArtsDistrict.enabled
	RcArtsDistrict.enabled = false
	var ch := CityChunk.new()
	var off := RcArtsDistrict.yard_car(ch, 0, Transform3D(), Color.WHITE)
	ch.free()
	RcArtsDistrict.enabled = was
	_t._check(not off and RcArtsDistrict.SPOUT_PAINT.get_luminance() < 0.3,
		"RcArtsDistrict: RC5_ARTS=0 leaves the yard cars in the batch; brick downspouts are dark")


func _row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "arts_district":
				row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 10.0 and (row.get("riders", []) as Array).size() >= 1,
		"RcArtsDistrict: the arts_district camera row is there at 10:00 with its riders")
