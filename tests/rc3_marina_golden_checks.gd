extends RefCounted
## The marina at golden hour (MarinaGolden, marina_mirror.gdshaderinc, BoatMesh's wires; the
## marina_golden reference camera in tools/refcams/cameras_w6.json; docs/HANDOFF.md "The marina at
## golden hour"), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## The boats handed to the water are the nearest, within reach, at most the shader's array; their
## packing is the boat's; the shader's array size is MarinaGolden's; rigging is its own region with
## its centre line in the mesh (two strips that agree), on NEAR and MID and never FAR; the boat
## material carries the switches; the camera row is there.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var mr: Marina = plan.macro.marina if plan.macro else null
	if mr == null or not MarinaGolden.enabled:
		_t._check(true, "marina golden: off (no marina or MARINA_GOLDEN=0), nothing to check")
		return
	_pick(mr)
	_shader()
	_wires()
	_camera()


func _pick(mr: Marina) -> void:
	var eye := Vector2(-621.5, 136.0)
	var got := MarinaGolden.pick(mr, eye)
	var near_ok := got.size() == mini(MarinaGolden.MAX_BOATS, mr.boats.size()) or got.size() > 0
	var sorted := true
	var last := -1.0
	for bt: Dictionary in got:
		var d := (bt.p as Vector2).distance_to(eye)
		if d < last - 1e-4 or d > MarinaGolden.REACH:
			sorted = false
		last = d
	# Nobody left out who is nearer than the farthest picked.
	var missed := 0
	for bt: Dictionary in mr.boats:
		if not got.has(bt) and (bt.p as Vector2).distance_to(eye) < last - 1e-3:
			missed += 1
	_t._check(near_ok and sorted and missed == 0 and got.size() <= MarinaGolden.MAX_BOATS,
		"marina golden: %d boats picked nearest first within reach at the headwalk (%d nearer ones missed)" % [got.size(), missed])
	var far := MarinaGolden.pick(mr, Vector2(3000.0, 3000.0))
	_t._check(far.is_empty(), "marina golden: nothing picked with the camera across the basin from it (%d)" % far.size())
	var sail_ok := true
	var other_ok := true
	for bt: Dictionary in got:
		var row: Array = MarinaGolden.pack(bt)
		var a: Vector4 = row[0]
		var b: Vector4 = row[1]
		var p: Vector2 = bt.p
		if absf(a.x - p.x) > 1e-3 or absf(a.y - p.y) > 1e-3 or absf(a.w - float(bt.len)) > 1e-3:
			other_ok = false
		if b.y <= 0.0 or b.z < b.y or b.x <= 0.0:
			other_ok = false
		if int(bt.type) == Marina.Type.SAIL and b.w < b.z + 8.0:
			sail_ok = false
	_t._check(other_ok and sail_ok, "marina golden: each boat packs its centre, length, beam, hull, cabin and a sailboat's mast over them")
	# The material takes the push.
	var node := MarinaGolden.new()
	var mat := ShaderMaterial.new()
	mat.shader = MarinaBuild.water_material().shader
	var n := node.push(mat, mr, eye)
	var cnt: int = mat.get_shader_parameter("mm_count")
	var arr: PackedVector4Array = mat.get_shader_parameter("mm_a")
	node.free()
	_t._check(n == got.size() and cnt == n and arr.size() == MarinaGolden.MAX_BOATS,
		"marina golden: the water gets mm_count %d and a %d-long array" % [cnt, arr.size()])


func _shader() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/marina_mirror.gdshaderinc")
	var water := FileAccess.get_file_as_string("res://shaders/marina_water.gdshader")
	var size_ok := inc.contains("const int MM_MAX = %d;" % MarinaGolden.MAX_BOATS) \
		and inc.contains("uniform vec4 mm_a[%d];" % MarinaGolden.MAX_BOATS) \
		and inc.contains("uniform vec4 mm_c[%d];" % MarinaGolden.MAX_BOATS)
	_t._check(size_ok and water.contains("#include \"res://shaders/marina_mirror.gdshaderinc\"") and water.contains("mm_count > 0"),
		"marina golden: the water traces the mirror, its arrays are MarinaGolden.MAX_BOATS long, and mm_count 0 keeps the old water")
	var bm := MarinaBuild.boat_material()
	_t._check(float(bm.get_shader_parameter("wire_px")) > 0.5 and float(bm.get_shader_parameter("jib_strip")) > 0.5,
		"marina golden: the boats' material widens the rigging and draws the jib covers")


func _wires() -> void:
	var counts := []
	var agree := true
	for level in 3:
		var m := BoatMesh.mesh(Marina.Type.SAIL, 0, level)
		var arr := m.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var n := 0
		for i in cols.size():
			if floori(cols[i].a * 16.0) != BoatMesh.Region.WIRE:
				continue
			n += 1
			if absf(ns[i].length() - 1.0) > 0.01 or uvs[i].x <= 0.0 or uvs[i].x > BoatMesh.WIRE_RADIUS * 2.0 + 1e-4:
				agree = false
		# A wire's two strips share a centre line: vertex - normal * half width.
		for i in range(0, cols.size() - 7):
			if floori(cols[i].a * 16.0) != BoatMesh.Region.WIRE or floori(cols[i + 4].a * 16.0) != BoatMesh.Region.WIRE:
				continue
			var c0 := vs[i] - ns[i] * uvs[i].x
			var c1 := vs[i + 4] - ns[i + 4] * uvs[i + 4].x
			if c0.distance_to(c1) > 1e-3:
				agree = false
			break
		counts.append(n)
	_t._check(counts[0] > 0 and counts[1] > 0 and counts[2] == 0 and agree,
		"marina golden: a sailboat's rigging is the WIRE region with its centre line in the mesh (NEAR %d, MID %d, FAR %d vertices)" % counts)


func _camera() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var found := false
	if data is Dictionary:
		for cam: Dictionary in data.get("cameras", []):
			if cam.get("name", "") == "marina_golden":
				found = absf(float(cam.hour) - 18.0) < 0.01 and cam.weather == "clear"
	_t._check(found, "marina golden: the reference camera's row is in cameras_w6.json (18:00, clear)")
