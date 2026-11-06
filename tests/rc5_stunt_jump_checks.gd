extends RefCounted
## The stunt_jump refcam (StuntJumpFX; docs/HANDOFF.md "The stunt jump off the freeway pair"):
## checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_row(plan)
	_flights(plan)
	_hang()
	_plate()
	_bursts(city)
	await t.get_tree().process_frame
	_crowns(city, plan)


## The camera row: on cameras_w8.json, staged, its site real.
func _row(plan: CityPlan) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var row: Dictionary = {}
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for c: Dictionary in data.get("cameras", []):
				if String(c.get("name", "")) == "stunt_jump":
					row = c
	var site := String((row.get("stunt", {}) as Dictionary).get("site", "")) if row.get("stunt", null) is Dictionary else ""
	var found := false
	for s: Dictionary in StuntRamps.all_sites(plan):
		if String(s.id) == site and int(s.kind) == StuntRamps.Kind.LAUNCH:
			found = true
	_t._check(not row.is_empty() and String(row.get("stage", "")) == "stunt" and found,
		"stunt jump: cameras_w8.json has the stunt_jump row, staged on launch site %s" % site)


## Every launch carries its flight box, pure, covering its lip and its landing's top.
func _flights(plan: CityPlan) -> void:
	var sites := StuntRamps.freeway_sites(plan)
	var bad := 0
	var n := 0
	for i in sites.size():
		var s: Dictionary = sites[i]
		if int(s.kind) != StuntRamps.Kind.LAUNCH:
			continue
		n += 1
		var land: Dictionary = sites[i + 1]
		if not s.has("flight"):
			bad += 1
			continue
		var f: Dictionary = s.flight
		var lip := StuntBuild.xform(s) * (StuntRamps.lips(s)[0][0] as Vector3)
		var top := StuntBuild.xform(land) * Vector3(0.0, 0.0, 3.0)
		var end := StuntBuild.xform(land) * Vector3(0.0, 0.0, float(land.len))
		for p: Vector3 in [lip, top, end]:
			if not StuntJumpFX.in_flight(f, Vector2(p.x, p.z)):
				bad += 1
		var again := StuntJumpFX.flight_box(Vector2(s.p.x, s.p.z), f.dir, Vector2(end.x, end.z), float(s.w))
		if not (again.c as Vector2).is_equal_approx(f.c) or absf(float(again.hl) - float(f.hl)) > 0.3:
			bad += 1
	_t._check(n > 0 and bad == 0, "stunt jump: %d launches carry a flight box over their lip, the landing's top and end (%d bad)" % [n, bad])


## Airborne wheels hang to the stop; on the ground (or switched off) the springs' offset stands.
func _hang() -> void:
	var was := StuntJumpFX.enabled
	StuntJumpFX.enabled = true
	var full := StuntJumpFX.hang(-0.02, 1.0, 0.375)
	var ground := StuntJumpFX.hang(0.04, 0.0, 0.375)
	var early := StuntJumpFX.hang(-0.02, StuntJumpFX.HANG_SECONDS * 0.3, 0.375)
	var tight := StuntJumpFX.hang(0.0, 1.0, 0.1)
	StuntJumpFX.enabled = false
	var off := StuntJumpFX.hang(-0.02, 1.0, 0.375)
	StuntJumpFX.enabled = was
	_t._check(is_equal_approx(full, -StuntJumpFX.HANG) and is_equal_approx(ground, 0.04) and early < -0.02 and early > -StuntJumpFX.HANG
		and is_equal_approx(tight, -0.1) and is_equal_approx(off, -0.02),
		"stunt jump: an airborne wheel eases to the stop (%.3f, %.3f early), the ground and the A/B leave the springs (%.3f, %.3f), never past the travel (%.3f)" % [full, early, ground, off, tight])


func _plate() -> void:
	var m := StuntKit.material()
	var v: Variant = m.get_shader_parameter("look5")
	var src := FileAccess.get_file_as_string("res://shaders/stunt_ramp.gdshader")
	_t._check(src.contains("uniform float look5 = 0.0;") and float(v if v != null else 0.0) == (1.0 if StuntJumpFX.enabled else 0.0),
		"stunt jump: the tread plate's pass is a uniform defaulting off, set from StuntJumpFX.enabled (%s)" % str(v))


## A launch and a landing make their emitters (one-shot, emitting), under the scene, and go.
func _bursts(city: Node3D) -> void:
	var sites := StuntRamps.freeway_sites(city.plan)
	if sites.is_empty():
		return
	var s: Dictionary = sites[0]
	var stand := Node3D.new()
	city.add_child(stand)
	var was := StuntJumpFX.enabled
	StuntJumpFX.enabled = true
	var made := StuntJumpFX.launch(stand, s, Vector3(0.0, 15.0, 25.0), 0.4)
	var landed := StuntJumpFX.land(stand, WorldState.to_world(stand.global_position), Vector3(0.0, -8.0, 25.0))
	StuntJumpFX.enabled = false
	var none := StuntJumpFX.launch(stand, s, Vector3(0.0, 15.0, 25.0))
	StuntJumpFX.enabled = was
	var ok := made.size() == 4 and landed.size() == 2 and none.is_empty()
	for e: Variant in made + landed:
		var p := e as CPUParticles3D
		ok = ok and p != null and p.one_shot and p.emitting and p.is_inside_tree()
	_t._check(ok, "stunt jump: a launch makes 4 one-shot emitters, a landing 2, the A/B none (%d, %d, %d)" % [made.size(), landed.size(), none.size()])
	for e: Variant in made + landed:
		if is_instance_valid(e):
			(e as Node).queue_free()
	stand.queue_free()


## The chunk under the middle of a pair's flight keeps no tree crown in the air the car flies
## through.
func _crowns(city: Node3D, plan: CityPlan) -> void:
	var f: Dictionary = {}
	for s: Dictionary in StuntRamps.freeway_sites(plan):
		if s.has("flight"):
			f = s.flight
			break
	if f.is_empty():
		_t._check(false, "stunt jump: a flight box to check")
		return
	var c: Vector2 = f.c
	var dir: Vector2 = f.dir
	var left := 0
	var cleared := 0
	for off: float in [-float(f.hl) * 0.6, float(f.hl) * 0.6]:
		var at: Vector2 = c + dir * off
		var k := plan.chunk_index_at(at)
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		cleared += int(chunk.get_meta("stunt_flight_cleared", 0))
		for key: String in chunk._batch._batches:
			var crown := false
			for pre: String in StuntJumpFX.CROWN_KEYS:
				crown = crown or key.begins_with(pre)
			if not crown:
				continue
			for xf: Transform3D in chunk._batch._batches[key].xforms:
				if xf.basis.get_scale().x > 0.01 and StuntJumpFX.in_flight(f, Vector2(xf.origin.x, xf.origin.z)):
					left += 1
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	_t._check(left == 0, "stunt jump: no tree crown left standing in a pair's flight box (%d left, %d collapsed)" % [left, cleared])
