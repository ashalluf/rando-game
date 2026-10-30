extends RefCounted
## The hills' ground, fleet wave 3 (hill-ground-3, docs/HANDOFF.md "Hills without leopard spots,
## again"): checks for tests/smoke_test.gd. CPU and source only (no pixel can be read headless):
##   * the fine erosion's numbers agree between the shaders and HillPlanting, and HILL_GROUND_3=0
##     has a uniform to put back for every old number;
##   * the fine erosion runs DOWN the slope as rills, not in braids of pits (the leopard spots):
##     along the fall line it changes far less than across it;
##   * the chaparral stands are masses: on the front range a brush run along a row is many metres
##     long, where the old shrub-scale noise gave a speckle of 2-4 m runs that averaged to khaki;
##   * the code-built shrub (HillShrub) is a low, wide mound on a LOD ladder within its budget.
## Nothing here moves the player, the weather or the clock.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_mirrors()
	_rills()
	var plan: CityPlan = city.get("plan") if city else null
	if plan and plan.macro:
		_masses(plan)
	_shrub()


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _uniform(src: String, name: String) -> float:
	var m := RegEx.create_from_string("uniform float " + name + "\\b[^=]*=\\s*([0-9.]+)").search(src)
	return m.get_string(1).to_float() if m else NAN


func _mirrors() -> void:
	var ero := _src("res://shaders/erosion.gdshaderinc")
	var terrain := _src("res://shaders/terrain.gdshader")
	var plane := _src("res://shaders/macro_ground.gdshader")
	var shells := _src("res://shaders/hill_shells.gdshader")
	var splat := _src("res://shaders/hill_splat.gdshaderinc")
	var bad: Array[String] = []
	if absf(_uniform(ero, "erosion_jitter") - HillPlanting.EROSION_JITTER) > 1e-6:
		bad.append("erosion_jitter")
	if absf(_uniform(ero, "erosion_branch") - HillPlanting.EROSION_BRANCH) > 1e-6:
		bad.append("erosion_branch")
	if absf(_uniform(terrain, "erosion_amp") - HillPlanting.EROSION_AMP) > 1e-6:
		bad.append("erosion_amp")
	if absf(_uniform(plane, "far_erosion_amp") - HillPlanting.EROSION_AMP) > 1e-6:
		bad.append("far_erosion_amp")
	if absf(_uniform(terrain, "erosion_cell") - HillPlanting.EROSION_CELL) > 1e-6:
		bad.append("erosion_cell")
	# Every old number the A/B puts back is a uniform somewhere in the hill ground shaders.
	var all := ero + terrain + plane + shells + splat
	for k: String in HillGround3.OLD:
		if is_nan(_uniform(all, k)):
			bad.append("OLD." + k)
	# The rills reach every surface that paints the stands: the tiles, the shells, the plane.
	for pair: Array in [["terrain", terrain], ["shells", shells], ["plane", plane]]:
		if not String(pair[1]).contains("hill_rill_th("):
			bad.append(pair[0] + " without hill_rill_th")
	_t._check(bad.is_empty(), "hill-ground-3: the fine erosion and the rills agree across the shaders and HillPlanting (%s)" % (", ".join(bad) if bad else "all match"))


## Mean |change| of the rill field per metre along `dir`, over a patch of a steady slope.
func _variation(grad: Vector2, dir: Vector2) -> float:
	var sum := 0.0
	var n := 0
	for k in 60:
		var p := Vector2(137.0 + float(k % 10) * 23.7, -1210.0 + float(k / 10) * 31.3)
		var a := HillPlanting.rill(p, grad, HillPlanting._weights().amp)
		var b := HillPlanting.rill(p + dir * 2.0, grad, HillPlanting._weights().amp)
		sum += absf(b - a) * 0.5
		n += 1
	return sum / n


func _rills() -> void:
	var grad := Vector2(0.15, 0.42)
	var fall := grad.normalized()
	var across := Vector2(-fall.y, fall.x)
	var ratio := _variation(grad, fall) / maxf(_variation(grad, across), 1e-6)
	var was := HillGround3.enabled
	HillGround3.enabled = false
	HillPlanting._w = {}
	var old := _variation(grad, fall) / maxf(_variation(grad, across), 1e-6)
	HillGround3.enabled = was
	HillPlanting._w = {}
	_t._check(ratio < 0.45 and ratio < old, "hill-ground-3: the fine erosion runs down the slope as rills (variation along / across the fall line %.2f, braided before %.2f)" % [ratio, old])


## Brush along rows across the front range's south face: [mean run length in metres of brush over
## 0.5, share of the ground in the soft middle (0.2..0.8)].
func _rows(plan: CityPlan) -> Vector2:
	var step := 2.0
	var runs := 0
	var run_m := 0.0
	var cur := 0.0
	var mid := 0
	var total := 0
	for z: float in [-1150.0, -1020.0, -1300.0]:
		for i in 300:
			var w := Vector2(-150.0 + i * step, z)
			var h := plan.height_at(w)
			var drain: float = plan.macro.last_drain
			if h < 30.0:
				if cur > 0.0:
					runs += 1
					run_m += cur
					cur = 0.0
				continue
			var grad := Vector2(plan.height_at(w + Vector2(2.0, 0.0)) - plan.height_at(w - Vector2(2.0, 0.0)),
				plan.height_at(w + Vector2(0.0, 2.0)) - plan.height_at(w - Vector2(0.0, 2.0))) * 0.25
			var g := HillPlanting.ground(w, grad, false, drain)
			var b := float(g.brush)
			total += 1
			if b > 0.2 and b < 0.8:
				mid += 1
			if b > 0.5:
				cur += step
			elif cur > 0.0:
				runs += 1
				run_m += cur
				cur = 0.0
		if cur > 0.0:
			runs += 1
			run_m += cur
			cur = 0.0
	return Vector2(run_m / maxf(runs, 1.0), float(mid) / maxf(total, 1.0))


func _masses(plan: CityPlan) -> void:
	var now := _rows(plan)
	var was := HillGround3.enabled
	HillGround3.enabled = false
	HillPlanting._w = {}
	var old := _rows(plan)
	HillGround3.enabled = was
	HillPlanting._w = {}
	_t._check(now.x >= 10.0 and now.x > old.x * 1.5,
		"hill-ground-3: the chaparral stands are masses (mean brush run %.1f m along the front range, %.1f m before; %d%% of the ground in the soft middle, %d%% before)" % [now.x, old.x, int(now.y * 100.0), int(old.y * 100.0)])


func _shrub() -> void:
	var m := HillShrub.mesh(0)
	var data := HillShrub._grow(0)
	var lv0: Array = LaTrees._emit(data, LaTrees.LEVELS[0])
	var lv4: Array = LaTrees._emit(data, LaTrees.LEVELS[LaTrees.LEVELS.size() - 1])
	var tris0 := (lv0[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var tris4 := (lv4[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	# The leaves' own bounds (the mesh's box also holds the far levels' cluster cards).
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p: Vector3 in lv0[Mesh.ARRAY_VERTEX]:
		lo = lo.min(p)
		hi = hi.max(p)
	var width := minf(hi.x - lo.x, hi.z - lo.z)
	var low_wide := absf(hi.y - HillShrub.HEIGHT) < HillShrub.HEIGHT * 0.15 and width > hi.y * 1.25 and lo.y < 0.3
	_t._check(low_wide and tris0 < 9000 and tris4 * 8 < tris0 and m.has_meta("foliage_ladder") and PropFactory._shadow_proxies.has(m),
		"hill-ground-3: the chaparral shrub is a low wide mound on a LOD ladder (%.1f m wide, %.1f m tall against HEIGHT %.1f, %d -> %d triangles)" % [width, hi.y, HillShrub.HEIGHT, tris0, tris4])
