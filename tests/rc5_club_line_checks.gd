extends RefCounted
## The club line at 23:30 (RcClubLine, the club_line reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the camera row (hour, staging keys); the beam shader starts the shaft at the lens when
## nothing hands it to the fog, with a core that thins up the sky, and a SkyBeam wears the look;
## the lens-wide cone; the fascia board (black face, LED frame, sized to the shop); the club the
## camera looks at, built at 23:30 with its opening: a club with its board, the name over the sign
## band, the searchlights; RC5_CLUB_LINE=0 is the old look.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := RcClubLine.enabled
	RcClubLine.enabled = true
	var plan: CityPlan = city.get("plan")
	var row := _camera()
	_shader()
	_meshes()
	if not row.is_empty():
		_chunk(city, plan, row)
	RcClubLine.enabled = false
	var m := ShaderMaterial.new()
	RcClubLine.beam(m, 1700.0)
	_t._check(RcClubLine.cone(17.0) == null and m.get_shader_parameter("club_look") == null,
		"RC5_CLUB_LINE=0: the beam keeps its old cone and look")
	RcClubLine.enabled = was


func _camera() -> Dictionary:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in table.get("cameras", []):
		if String(c.name) == "club_line":
			row = c
	var cl: Dictionary = row.get("club_line", {})
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 23.5) and int(cl.get("opening", 0)) == 1
		and (cl.get("pickups", {}) as Dictionary).get("cars", []).size() >= 2,
		"the club_line camera is in cameras_w8.json at 23:30 with the opening and two pickups staged")
	return row


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/nightlife_beam.gdshader")
	_t._check(src.contains("uniform float club_look") and src.contains("club_look > 0.5 && near_start <= 0.0")
		and src.contains("core_gain") and src.contains("club_fade"),
		"the beam starts at the lens with no fog to hand it to, a core thinning up the sky")
	var m := ShaderMaterial.new()
	RcClubLine.beam(m, 1700.0)
	_t._check(float(m.get_shader_parameter("club_look")) > 0.5 and is_equal_approx(float(m.get_shader_parameter("beam_len")), 1700.0),
		"a searchlight's beam material wears the club look")


func _meshes() -> void:
	var wide := 1700.0 * tan(deg_to_rad(1.0))
	var cone := RcClubLine.cone(wide)
	_t._check(cone != null and absf(cone.top_radius * wide - RcClubLine.LENS_R) < 0.001,
		"the shaft leaves the lens lens-wide (%.2f m)" % (cone.top_radius * wide if cone else 0.0))
	var b := RcClubLine.board(5.2, 2)
	var arr := b.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var led := 0
	var face := 0
	for c in cols:
		var code := int(round(c.a * 20.0))
		if code == 4:
			led += 1
		elif code == 7:
			face += 1
	var box := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		box = box.expand(v)
	_t._check(led > 0 and face > 0 and absf(box.size.x - 5.2) < 0.05 and box.position.y > 3.3 and box.end.y < 4.4,
		"the fascia board: a black face, an LED frame, the shop's width over the sign band (%s)" % str(box))


func _chunk(city: Node, plan: CityPlan, row: Dictionary) -> void:
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var was_hour := NightLife.force_hour
	var was_events := NightLife.force_events
	NightLife.force_hour = 23.5
	NightLife.force_events = true
	# The club across 6th St from the eye: the block south of it.
	var k := plan.block_index_at(eye + Vector2(0.0, -30.0))
	var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
	chunk.build()
	var club: Dictionary = {}
	for v: Dictionary in chunk.get_meta("nightlife", []):
		if int(v.kind) == NightLife.Kind.CLUB and (v.door as Vector2).distance_to(eye) < 45.0:
			club = v
	_t._check(not club.is_empty() and bool(club.get("open", false)) and float(club.get("width", 0.0)) > 3.0,
		"the camera looks across the street at an open club (%s)" % String(club.get("name", "none")))
	var boards := 0
	for n in chunk.find_children("Batch_nl_board_*", "", true, false):
		boards += (n as MultiMeshInstance3D).multimesh.instance_count
	var big_name := false
	var beams := 0
	var looks := true
	var holder := chunk.get_node_or_null("NightLife")
	if holder:
		for n in holder.get_children():
			if n is MeshInstance3D and String(n.name).begins_with("NightSign") and absf((n as MeshInstance3D).global_position.y - chunk.global_position.y - CityChunk.SIDEWALK_TOP - (RcClubLine.BOARD_Y.x + RcClubLine.BOARD_Y.y) * 0.5) < 0.15:
				big_name = true
			if n is SkyBeam:
				beams += 1
				var shaft := n.find_child("Shaft", true, false) as MeshInstance3D
				looks = looks and shaft != null and shaft.material_override != null and float((shaft.material_override as ShaderMaterial).get_shader_parameter("club_look")) > 0.5
	_t._check(boards >= 1 and big_name, "the club takes its sign band: the board and the big name (%d boards)" % boards)
	_t._check(beams >= 2 and looks, "its opening's searchlights stand at the kerb, their shafts from the lens (%d)" % beams)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	NightLife.force_hour = was_hour
	NightLife.force_events = was_events
