extends RefCounted
## The freight yard refcam (RcFreightYard; camera `freight_yard` in tools/refcams/cameras_w7.json),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: a tie batch's draw range reaches past its farthest tie (the yard's ~520 m chunks hid
## every storage track's ties); a track piece laid northward keeps its ties on itself (the ladder's
## were thrown kilometres away); the ladder gets a ballast bed; a FULL yard chunk lays weeds in
## cells and draws its timbers; the ballast's crushed-rock pass and the cars' graffiti pass are in
## the shaders, off by default and switched on by the materials; the camera row stages the train;
## RC4_FREIGHT_YARD=0 puts the old numbers back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was: bool = RcFreightYard.enabled
	RcFreightYard.enabled = true
	_ranges()
	_ladder(city)
	_yard_chunk(city)
	_shaders()
	_camera()
	RcFreightYard.enabled = false
	var buf := PackedFloat32Array([1, 0, 0, 0.0, 0, 1, 0, 0, 0, 0, 1, 0.0, 1, 0, 0, 500.0, 0, 1, 0, 0, 0, 0, 1, 0.0])
	_t._check(is_equal_approx(RcFreightYard.tie_range(buf, 260.0), 260.0), "RC4_FREIGHT_YARD=0: the ties' old 260 m draw range")
	RcFreightYard.enabled = was


func _ranges() -> void:
	var buf := PackedFloat32Array([1, 0, 0, 0.0, 0, 1, 0, 0, 0, 0, 1, 0.0, 1, 0, 0, 300.0, 0, 1, 0, 0, 0, 0, 1, 400.0])
	var r := RcFreightYard.tie_range(buf, 260.0)
	_t._check(r >= 260.0 + 249.0, "a tie batch's draw range reaches 260 m past its farthest tie, not its centre (%.0f m)" % r)


func _ladder(city: Node3D) -> void:
	var plan: CityPlan = city.get("plan")
	var line := FreightRail.of(plan)
	if line == null:
		_t._check(false, "the freight line resolves for the yard checks")
		return
	var lay := FreightYard.layout(line)
	var a: Vector2 = lay.ladder[0]
	var b: Vector2 = lay.ladder[1]
	var key := plan.chunk_index_at((a + b) * 0.5)
	var c: CityChunk = city.call("_new_chunk", key, CityChunk.Level.FULL)
	var kit := FreightKit.new(c)
	# A piece laid northward (za > zb), as the ladder is walked.
	var p0 := a.lerp(b, 0.5)
	var p1 := a.lerp(b, 0.55)
	kit.ties(p0.x, p0.y, p1.x, p1.y, 11.0, 11.0, true)
	var buf: PackedFloat32Array = kit.get("_timbers")
	var n := buf.size() / 12
	var on := n > 0
	for i in n:
		var p := Vector2(buf[i * 12 + 3], buf[i * 12 + 11])
		var seg := Geometry2D.get_closest_point_to_segment(p, p0, p1)
		if p.distance_to(seg) > 0.05:
			on = false
	_t._check(on, "a track piece laid northward keeps its %d ties on itself (the ladder's were kilometres off)" % n)
	kit.set("_track_any", false)
	RcFreightYard.ladder_ballast(kit, p0, p1, 11.0, 11.0, 10.35, 10.35)
	_t._check(bool(kit.get("_track_any")), "the ladder gets a ballast bed under its rails")
	if c.get_parent():
		c.get_parent().remove_child(c)
	c.free()


func _yard_chunk(city: Node3D) -> void:
	var plan: CityPlan = city.get("plan")
	var line := FreightRail.of(plan)
	if line == null:
		return
	var lay := FreightYard.layout(line)
	var spots := RcFreightYard.stand_spots(lay)
	var a: Vector2 = lay.ladder[0]
	var b: Vector2 = lay.ladder[1]
	var on_bed := spots.size() == (lay.tracks as Array).size()
	for p: Vector2 in spots:
		# On the ladder's bed (1.95 m half width), off its tie ends (1.3 m).
		var dl := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if dl < 1.35 or dl > FreightKit.BALLAST_HALF:
			on_bed = false
	_t._check(on_bed, "a switch stand on the ladder's bed at each of the %d turnouts, off the tie ends" % spots.size())
	var vs := RcFreightYard.valleys(lay)
	_t._check(vs.size() >= 4, "the valleys between neighbouring storage beds are filled (%d)" % vs.size())
	var shoulder_out := RcFreightYard.in_storage(Vector2(float(lay.tracks[0].x) + 2.5, float(lay.tracks[0].z1) - 20.0), lay.tracks)
	_t._check(shoulder_out, "the ladder's shoulder is left out among the storage beds")
	var t1: Dictionary = lay.tracks[3]
	var key := plan.chunk_index_at(Vector2(float(t1.x), (float(t1.z0) + float(t1.z1)) * 0.5))
	var c: CityChunk = city.call("_new_chunk", key, CityChunk.Level.FULL)
	c.build()
	var weeds := 0
	var cells := {}
	var timber_range := 0.0
	for nd in c.get_children():
		var nm := str(nd.name)
		if nd is MultiMeshInstance3D and nm.begins_with("Batch_fy_tuft_"):
			weeds += (nd as MultiMeshInstance3D).multimesh.instance_count
			cells[nm] = true
		if nm == "FreightTimbers":
			timber_range = (nd as GeometryInstance3D).visibility_range_end
	_t._check(weeds > 50 and cells.size() >= 2, "a FULL yard chunk lays %d weed tufts in %d cell batches" % [weeds, cells.size()])
	_t._check(timber_range > 300.0, "the yard chunk's timber ties draw past the batch's centre (%.0f m)" % timber_range)
	c.get_parent().remove_child(c)
	c.free()


func _shaders() -> void:
	var tr := FileAccess.get_file_as_string("res://shaders/freight_track.gdshader")
	_t._check(tr.contains("uniform float rc4 = 0.0;") and tr.contains("vec4 rocks(vec2 p, out vec2 rr)"),
		"the ballast's crushed-rock pass is in the track shader, off by default")
	var st := FileAccess.get_file_as_string("res://shaders/freight_stock.gdshader")
	_t._check(st.contains("uniform float rc4 = 0.0;") and st.contains("vec3 freight_tags("),
		"the cars' graffiti and panel weathering are in the stock shader, off by default")
	var tm := FreightKit.track_material()
	var sm := FreightStock.material()
	_t._check(float(tm.get_shader_parameter("rc4")) == 1.0 and float(sm.get_shader_parameter("rc4")) == 1.0
		and sm.get_shader_parameter("tag_atlas") is Texture2D, "the track and stock materials switch their passes on, the tag atlas bound")


func _camera() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var row: Dictionary = {}
	for cam: Dictionary in (data as Dictionary).cameras:
		if String(cam.name) == "freight_yard":
			row = cam
	_t._check(not row.is_empty() and float(row.get("freight_into", 0.0)) > float(FreightRail.DWELL_YARD),
		"the freight_yard camera row holds the train pulling out (past the %.0f s stand)" % FreightRail.DWELL_YARD)
	var src := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(src.contains("func _freight_clock("), "refcams_shot stages the freight line's clock for a freight_into row")
