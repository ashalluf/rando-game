extends RefCounted
## A high school stadium on a game night (FridayLights, the friday_lights reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row stands at the edge of a game-night high school's car park; the lineup
## (two teams of eleven either side of a line of scrimmage on the field, officials, the benches on
## the sidelines); a car park no one chunk holds is built whole by the chunk owning its middle and
## filled; every lit standard has a spotlight aimed down at the field and a bloom; the lights follow
## the lamp level; RC5_FRIDAY_LIGHTS=0 builds the stadium as before (no rig, no school lot cars).
## The players and the crowd are baked from mesh data, which the headless check does not keep.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var plan: Variant = city.get("plan")
	if plan == null:
		_t._check(false, "friday_lights: the city has a plan")
		return
	var school := _camera(plan)
	if school.is_empty():
		return
	var pl: Dictionary = school.pl
	var track: Dictionary = school.track
	_lineup(pl, track)
	_stadium(city, plan, pl, track)
	_car_park(city, plan, pl, school.parking)


## The camera row, and the school it looks at: {pl, track, parking} or {}.
func _camera(plan: CityPlan) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (data as Dictionary).get("cameras", []):
		if c.get("name", "") == "friday_lights":
			row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 20.0) and row.get("weather", "") == "clear",
		"the friday_lights camera row is there, 20:00 clear")
	if row.is_empty():
		return {}
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var d := Schools.decide(plan, Schools._cell_of(eye))
	_t._check(not d.is_empty() and bool(d.get("high", false)), "friday_lights looks at a high school (%s)" % [d.get("cell", "none")])
	if d.is_empty():
		return {}
	var pl := Schools.plan_for_school(plan, d)
	_t._check(bool(pl.game_night), "%s has a game night" % pl.full_name)
	var out := {"pl": pl}
	for f: Dictionary in pl.fac:
		if f.t == "track":
			out.track = f
		elif f.t == "parking":
			out.parking = f.r
	_t._check(out.has("track") and out.has("parking"), "the school has a stadium and a car park")
	if not out.has("track") or not out.has("parking"):
		return {}
	var lot: Rect2 = out.parking
	_t._check(lot.grow(3.0).has_point(eye) and not (out.track.r as Rect2).has_point(eye),
		"the friday_lights eye stands at the edge of the car park (%s, lot %s)" % [str(eye), str(lot)])
	var yaw := deg_to_rad(float(row.eye[3]))
	var look := Vector2(-sin(yaw), -cos(yaw))
	var to_field: Vector2 = (out.track.r as Rect2).get_center() - eye
	_t._check(look.dot(to_field.normalized()) > 0.8, "the camera looks at the field")
	return out


func _lineup(pl: Dictionary, f: Dictionary) -> void:
	var people := FridayLights.line_up(pl, f)
	var teams := [0, 0, 0]
	var ok := true
	var half_l := Parks.FOOTBALL.x * 0.5 * float(f.football) + 12.0
	var half_w := Parks.FOOTBALL.y * 0.5 * float(f.football) + 8.0
	var los_side := [0.0, 0.0]
	for p: Array in people:
		teams[int(p[2])] += 1
		if absf(float(p[0])) > half_l or absf(float(p[1])) > half_w:
			ok = false
	# The first 22 are the two lines: offence behind the line (smaller a), defence beyond it.
	var los: float = people[0][0]
	for i in 11:
		if float(people[i][0]) > los + 0.01 or float(people[11 + i][0]) < los - 0.01:
			ok = false
	_t._check(teams[2] == 3 and teams[0] == 27 and teams[1] == 27 and ok,
		"the lineup: eleven a side either side of the line, the benches, three officials, all on the field or its sidelines (%s)" % [str(teams)])
	_t._check(FridayLights.line_up(pl, f) == people, "the lineup is a pure function of the school")


func _chunk_at(plan: CityPlan, p: Vector2) -> Vector2i:
	var k := plan.block_index_at(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if plan.owned_rect(k.x + dx, k.y + dz).has_point(p):
				return Vector2i(k.x + dx, k.y + dz)
	return k


func _stadium(city: Node, plan: CityPlan, pl: Dictionary, f: Dictionary) -> void:
	# The east standard nearest the car park: its chunk.
	var ext: float = f.R + float(f.lanes) * Parks.LANE + Parks.TRACK_APRON * 0.6
	var foot := Parks.fp(f, f.S * 0.45, ext)
	var k := _chunk_at(plan, foot)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var rig := chunk.get_node_or_null("FridayLights") as FridayRig
	_t._check(rig != null and rig.banks.size() >= 1, "a game night's lit standard gets the Friday rig (%d banks)" % (rig.banks.size() if rig else 0))
	if rig:
		var down := true
		for s: SpotLight3D in rig.spots:
			var dir := -s.transform.basis.z
			if dir.y > -0.15 or dir.y < -0.95:
				down = false
		_t._check(rig.spots.size() == rig.banks.size() and down, "each lit standard throws a spotlight down onto the field (%d)" % rig.spots.size())
		var was := DayNight.lamp_now
		DayNight.lamp_now = 1.0
		rig._timer = 0.0
		rig._process(0.5)
		var lit := rig.spots.size() > 0 and (rig.spots[0] as SpotLight3D).visible and (rig.spots[0] as SpotLight3D).light_energy > 1.0
		DayNight.lamp_now = 0.0
		rig._timer = 0.0
		rig._process(0.5)
		var dark := rig.spots.is_empty() or not (rig.spots[0] as SpotLight3D).visible
		DayNight.lamp_now = was
		_t._check(lit and dark, "the spotlights are on after dark and off by day")
		var bloom := rig.get_node_or_null("FridayBloom") as MeshInstance3D
		_t._check(bloom != null and bloom.mesh != null and bloom.mesh.get_surface_count() == 1, "the standards' blooms are one mesh")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# The A/B: none of it.
	FridayLights._enabled = 0
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	_t._check(off.get_node_or_null("FridayLights") == null, "RC5_FRIDAY_LIGHTS=0: no rig")
	off.get_parent().remove_child(off)
	off.free()
	FridayLights._enabled = 1


func _car_park(city: Node, plan: CityPlan, pl: Dictionary, lot: Rect2) -> void:
	var k := _chunk_at(plan, lot.get_center())
	var whole := plan.owned_rect(k.x, k.y).encloses(lot)
	var counts := []
	for on in [1, 0]:
		FridayLights._enabled = on
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		counts.append(chunk._fill_cars)
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	FridayLights._enabled = 1
	# Stall rows of the school's lot (two rows of STALL.x across the long side).
	var stalls := 2 * int((maxf(lot.size.x, lot.size.y) - 2.4 - 2.0) / LotFill.STALL.x)
	if whole:
		_t._check(counts[0] >= counts[1], "a school lot one chunk holds: at least as full on a game night (%s)" % [str(counts)])
	else:
		_t._check(counts[0] - counts[1] >= int(stalls * 0.8), "a school car park across a chunk border is built whole and full on a game night (%d more cars, %d stalls)" % [counts[0] - counts[1], stalls])
