extends RefCounted
## The ballpark in the ravine (Ballpark, BallparkBuild), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Where: home plate at the real one's point through DowntownReal, facing the real way, in the
## embayed hills north of downtown, the whole site on hill ground and clear of the freeways, the
## estates and every other hill road. The ground: the pad and the terrace at their levels, banks
## with no cliff, the hills' planting and shells kept off it. The roads: drivable grades, Stadium
## Way down to Hill St, the north drive to the valley. The numbers the shaders copy are the
## script's, the stall hash is the same arithmetic. The meshes: within budgets, the far copy
## cheap, collision for the stands, a FULL chunk builds it detailed. Nothing is named for a real
## team, venue or sponsor.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	_t._check(Ballpark.enabled() and Landmarks.all().any(func(lm: Dictionary) -> bool: return lm.id == "ballpark"),
		"the ballpark is a landmark")
	_place()
	_ground(macro)
	_clear(macro)
	_roads(macro)
	_copies()
	_meshes()
	_chunk(city, plan)
	_names()


func _place() -> void:
	var home := DowntownReal.game_xz(Vector2(34.07328, -118.24065))
	var cf := DowntownReal.game_xz(Vector2(34.07505, -118.23935))
	var dir := (cf - home).normalized()
	_t._check(home.distance_to(Ballpark.HOME) < 2.0 and rad_to_deg(dir.angle_to(Ballpark.FWD)) < 1.0
		and absf(Ballpark.RIGHT.dot(Ballpark.FWD)) < 1e-3,
		"home plate stands at the real one's point (%.1f m off), facing the real centre field (%.2f deg)" % [home.distance_to(Ballpark.HOME), rad_to_deg(absf(dir.angle_to(Ballpark.FWD)))])
	# At 1:1 from Pershing Square, north of the civic centre and the 101.
	var real := DowntownReal.real_en(Vector2(34.07328, -118.24065)).length()
	var game := Ballpark.HOME.distance_to(DowntownReal.GAME_ANCHOR)
	var hall := DowntownReal.point("200_n_spring")
	_t._check(absf(real - game) < 5.0 and Ballpark.HOME.y < hall.y - 1000.0 and Ballpark.HOME.y < -1700.0,
		"the ballpark is %.0f m from Pershing Square in the game, %.0f m in life, north of the civic centre" % [game, real])
	_t._check(is_equal_approx(Ballpark.fence_r(0.0), Ballpark.FENCE_CENTER) and is_equal_approx(Ballpark.fence_r(45.0), Ballpark.FENCE_LINE)
		and is_equal_approx(Ballpark.fence_r(-22.5), Ballpark.FENCE_ALLEY) and absf(Ballpark.BASE - 27.432) < 0.001,
		"the field is regulation: 90 ft bases, 330 / 375 / 395 ft to the fence")


func _ground(macro: MacroMap) -> void:
	var hills := 0
	var samples := 0
	var off := 0.0
	var u := -Ballpark.SITE_U + 15.0
	while u < Ballpark.SITE_U:
		var v := Ballpark.SITE_V0 + 15.0
		while v < Ballpark.SITE_V1:
			var q := Vector2(u, v)
			if Ballpark.site_sd(q) < -2.0:
				var p := Ballpark.world(u, v)
				samples += 1
				if macro.zone_at(p) == MacroMap.Zone.HILLS:
					hills += 1
				off = maxf(off, absf(macro.height_at(p) - Ballpark.level(q)))
				if not Ballpark.covers(p):
					off = 999.0
			v += 30.0
		u += 30.0
	_t._check(samples > 300 and hills == samples and off < 0.05,
		"the site (%d samples) is all hill ground, cut to its levels (worst %.2f m off)" % [samples, off])
	# The banks: no cliff steeper than the cut slope plus the shoulder's roll, all the way round.
	var worst := 0.0
	for i in 720:
		var a := TAU * i / 720.0
		var dir := Vector2(sin(a), cos(a))
		var r := 40.0
		var q := Vector2(0.0, 35.0)
		while Ballpark.site_sd(q + dir * r) < 0.0:
			r += 4.0
		var prev := macro.height_at(Ballpark.world(q.x + dir.x * r, q.y + dir.y * r))
		for k in 30:
			var rr := r + 2.0 + k * 2.0
			var h := macro.height_at(Ballpark.world(q.x + dir.x * rr, q.y + dir.y * rr))
			worst = maxf(worst, absf(h - prev) / 2.0)
			prev = h
	_t._check(worst < 1.9, "the banks round the site are graded (steepest %.2f m per metre)" % worst)
	var p := Ballpark.world(0.0, 60.0)
	_t._check(Ballpark.covers(p) and not Ballpark.covers(Ballpark.world(0.0, Ballpark.SITE_V1 + 40.0))
		and Ballpark.shell_marks(Rect2(p - Vector2(50.0, 50.0), Vector2(100.0, 100.0))).size() > 5,
		"the hills' planting, scatter and shells keep off the site")


func _clear(macro: MacroMap) -> void:
	var hit := ""
	for fr in macro.freeway.routes:
		for pt: Vector2 in fr.points:
			if Ballpark.covers(pt, 40.0):
				hit = "freeway %s at %s" % [fr.name, pt]
				break
	for m in macro.hill_roads.mansions:
		if Ballpark.covers(m.pos, 40.0):
			hit = "estate at %s" % m.pos
	for r in macro.hill_roads.roads:
		if r.get("ballpark", false):
			continue
		for pt: Vector2 in r.points:
			if Ballpark.covers(pt, 20.0):
				hit = "hill road %s at %s" % [r.name, pt]
	_t._check(hit == "", "no freeway, estate or other hill road on the site (%s)" % (hit if hit != "" else "clear"))


func _roads(macro: MacroMap) -> void:
	for rn: String in ["Sunridge Dr", "Stadium Way"]:
		var r := Ballpark.road(macro, rn)
		if r.is_empty():
			_t._check(false, "the ballpark's road %s exists" % rn)
			continue
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		var grade := 0.0
		for i in range(1, pts.size()):
			grade = maxf(grade, absf(hs[i] - hs[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 0.01))
		var start_ok := absf(hs[0] - Ballpark.level(Ballpark.local(pts[0]))) < 0.01
		var end_ok := true
		if rn == "Stadium Way":
			end_ok = absf(pts[pts.size() - 1].x - 2864.4) < 1.0 and macro.zone_at(pts[pts.size() - 1]) == MacroMap.Zone.CITY
		else:
			end_ok = macro.zone_at(pts[pts.size() - 1]) == MacroMap.Zone.CITY or macro.plateau_at(pts[pts.size() - 1]) > 50.0
		_t._check(grade <= Ballpark.ROAD_GRADE + 0.001 and start_ok and end_ok and r.width == Ballpark.ROAD_WIDTH,
			"%s: from the site's level to the city, steepest grade %.1f %%" % [rn, grade * 100.0])


func _copies() -> void:
	var field := FileAccess.get_file_as_string("res://shaders/ballpark_field.gdshader")
	var lot := FileAccess.get_file_as_string("res://shaders/ballpark_lot.gdshader")
	var common := FileAccess.get_file_as_string("res://shaders/ballpark_common.gdshaderinc")
	var pairs := {
		"fence_line": Ballpark.FENCE_LINE, "fence_alley": Ballpark.FENCE_ALLEY, "fence_center": Ballpark.FENCE_CENTER,
		"base": Ballpark.BASE, "rubber": Ballpark.RUBBER, "mound_r": Ballpark.MOUND_R, "arc_r": Ballpark.ARC_R,
		"track": Ballpark.TRACK, "front": Ballpark.FRONT,
	}
	var bad := []
	for k: String in pairs:
		if not _has_uniform(field, k, pairs[k]):
			bad.append("field " + k)
	var lot_pairs := {
		"lot_v0": Ballpark.SITE_V0, "lot_u0": -Ballpark.SITE_U, "module": Ballpark.LOT_MODULE, "stall_d": Ballpark.LOT_STALL_D,
		"stall_w": Ballpark.LOT_STALL_W, "block_u": Ballpark.LOT_BLOCK_U, "block_stalls": Ballpark.LOT_STALL_W * Ballpark.LOT_BLOCK_STALLS_N,
		"plaza_bowl": Ballpark.PLAZA_BOWL, "plaza_fair": Ballpark.PLAZA_FAIR, "ring": Ballpark.RING,
		"terrace_r": Ballpark.TERRACE_R, "slope_run": Ballpark.SLOPE_RUN, "terrace_v0": Ballpark.TERRACE_V0, "terrace_v1": Ballpark.TERRACE_V1,
		"fence_line": Ballpark.FENCE_LINE, "fence_alley": Ballpark.FENCE_ALLEY, "fence_center": Ballpark.FENCE_CENTER,
	}
	for k: String in lot_pairs:
		if not _has_uniform(lot, k, lot_pairs[k]):
			bad.append("lot " + k)
	if lot.find("float(Ballpark.EDGE_PLANTING)") < 0 and lot.find("e > -%.1f" % Ballpark.EDGE_PLANTING) < 0:
		bad.append("lot edge planting")
	if common.find("0x7feb352du") < 0 or common.find("0x846ca68bu") < 0 or common.find("* 7919u") < 0:
		bad.append("hash")
	_t._check(bad.is_empty(), "the field and lot shaders' copies match Ballpark (%s)" % (", ".join(bad) if not bad.is_empty() else "all"))
	# The stall hash, as the shader computes it (reference values from the same lowbias32).
	_t._check(Ballpark.ihash(0, 0) == 3820432825 and Ballpark.ihash(123, 45) == 113667735 and Ballpark.ihash(7027, 9) == 4270734778,
		"the stall hash is lowbias32, as the lot shader rolls it")


func _has_uniform(src: String, uname: String, value: float) -> bool:
	var re := RegEx.new()
	re.compile("uniform (?:float|vec2) " + uname + " = (-?[0-9.]+)")
	var m := re.search(src)
	return m != null and absf(float(m.get_string(1)) - value) < 0.001


func _meshes() -> void:
	var near: Dictionary = BallparkBuild._meshes("near")
	var far: Dictionary = BallparkBuild._meshes("far")
	var tn := _tris(near)
	var tf := _tris(far)
	_t._check(tn > 25000 and tn < 70000 and tf < 12000 and (near.collision as PackedVector3Array).size() > 3000 and not far.has("collision"),
		"the bowl, pavilions, field and lots: %d triangles near, %d far; collision near only" % [tn, tf])
	var cars := 0
	for v in range(0, 200, 7):
		for u in range(-280, 280, 3):
			if Ballpark.stall_car(Vector2(u, Ballpark.SITE_V0 + v * 2.6)) >= 0:
				cars += 1
	_t._check(Ballpark.poles().size() > 30 and Ballpark.palm_spots().size() > 80 and cars > 50,
		"the lots carry poles (%d), palms (%d) and parked cars" % [Ballpark.poles().size(), Ballpark.palm_spots().size()])


func _tris(c: Dictionary) -> int:
	var n := 0
	for k in c:
		if c[k] is ArrayMesh:
			var m: ArrayMesh = c[k]
			for si in m.get_surface_count():
				n += (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _chunk(city: Node3D, plan: CityPlan) -> void:
	var k := plan.chunk_index_at(Ballpark.anchor())
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var holder := chunk.get_node_or_null("Ballpark")
	var shape := chunk.find_child("BallparkShape", true, false)
	var lights := 0
	var cars := 0
	if holder:
		for c in holder.get_children():
			if c is OmniLight3D and c.is_in_group("lamp_light"):
				lights += 1
			if c is MultiMeshInstance3D and String(c.name).find("bp_car") >= 0:
				cars += (c as MultiMeshInstance3D).multimesh.instance_count
	_t._check(holder != null and shape != null and chunk.built_landmarks.has("ballpark") and cars > 100 and (lights >= 3 or OS.has_feature("web")),
		"the anchor's FULL chunk %s builds the detailed park: collision, %d parked cars, %d field lights" % [k, cars, lights])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _names() -> void:
	var banned := ["dodger", "chavez ravine stadium", "vin scully", "elysian park"]
	var found := []
	for path: String in ["res://scripts/world/ballpark.gd", "res://scripts/world/ballpark_build.gd", "res://shaders/ballpark_struct.gdshader",
			"res://shaders/ballpark_seats.gdshader", "res://shaders/ballpark_field.gdshader", "res://shaders/ballpark_lot.gdshader"]:
		var src := FileAccess.get_file_as_string(path).to_lower()
		for b: String in banned:
			if src.find(b) >= 0:
				found.append("%s in %s" % [b, path.get_file()])
	_t._check(found.is_empty(), "no real team, venue or person named in the ballpark (%s)" % (", ".join(found) if not found.is_empty() else "clean"))
