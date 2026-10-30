extends RefCounted
## Life in the water (SeaLife, SeaLifeMesh, SeaSounds, sea_life.gdshader, sea_spray.gdshader) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: every mesh builds inside its triangle budget with its part codes, the shader's part
## list and SeaLifeMesh agree, the sounds synthesise; the events are pure (the same pod, line and
## whale for the same window and stretch, every time) and the hashed odds come out near their
## numbers; every dolphin of a pod is out on open water beyond the break line, and some leap clear
## of the surface while others only roll; a staged pelican climbs to ~9 m, plunges and then sits
## on the water; the whale's blows come at their gaps and its flukes lift on the last dive; the
## buoys stand on open water clear of the cargo ship, their sea lions on the deck inside its rim,
## a bout barks; a startle sends them in and they come back; the draw puts out what is staged.

var _t: Node
var _tree: SceneTree
var _city: Node3D

const BUDGET := {"dolphin": [3200, 500], "sea_lion": [3000, 500], "pelican": [2600, 500], "whale": [3800, 700], "buoy": [4000, 600]}


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_meshes()
	_shader_parts()
	_sounds()
	var sea: Node = city.get_node_or_null("SeaLife")
	_t._check(sea != null and sea.get("enabled") == true, "sea life: the SeaLife node is in the city and on")
	if sea == null:
		return
	await _tree.process_frame
	var plan: CityPlan = city.get("plan")
	sea.call("setup_plan", plan)
	_events(sea, plan)
	_dolphins(sea, plan)
	_pelicans(sea, plan)
	_whale(sea, plan)
	await _buoys(sea, plan)
	await _draw(sea, plan)
	sea.call("clear_stage")


func _meshes() -> void:
	for k: String in BUDGET:
		for lod in 2:
			var m := SeaLifeMesh.mesh(k, lod)
			var tris := SeaLifeMesh.triangles(m)
			var budget: int = BUDGET[k][lod]
			_t._check(tris > 60 and tris <= budget, "sea life: the %s's level %d builds, %d triangles (budget %d)" % [k, lod, tris, budget])
		var arr := SeaLifeMesh.mesh(k, 0).surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var parts := {}
		for c in cols:
			parts[int(roundf(c.a * 16.0))] = true
		var want: Array = {"dolphin": [SeaLifeMesh.P_BODY, SeaLifeMesh.P_FIN], "sea_lion": [SeaLifeMesh.P_BODY, SeaLifeMesh.P_JAW, SeaLifeMesh.P_FIN],
			"pelican": [SeaLifeMesh.P_BODY, SeaLifeMesh.P_WING, SeaLifeMesh.P_BILL], "whale": [SeaLifeMesh.P_BODY, SeaLifeMesh.P_FIN],
			"buoy": [SeaLifeMesh.P_PAINT, SeaLifeMesh.P_LAMP, SeaLifeMesh.P_DECK, SeaLifeMesh.P_METAL]}[k]
		var ok := true
		for p in want:
			ok = ok and parts.has(p)
		_t._check(ok, "sea life: the %s carries its parts %s (found %s)" % [k, want, parts.keys()])
	# Real sizes: the dolphin 2.6 m nose to tail, the pelican's span ~2.1 m, the whale ~13 m.
	var sizes := {"dolphin": [2.4, 2.9, 2], "pelican": [1.9, 2.3, 0], "whale": [12.0, 14.5, 2], "sea_lion": [1.7, 2.1, 2]}
	for k: String in sizes:
		var box := SeaLifeMesh.mesh(k, 0).get_aabb()
		var r: Array = sizes[k]
		var size_m := box.size[int(r[2])]
		_t._check(size_m >= float(r[0]) and size_m <= float(r[1]), "sea life: the %s is real size (%.2f m)" % [k, size_m])
	var spray := SeaLifeMesh.mesh("spray", 0)
	_t._check(SeaLifeMesh.triangles(spray) == 28, "sea life: the spray is 14 clumps of two triangles")


## The shader's header lists the same part codes SeaLifeMesh writes.
func _shader_parts() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sea_life.gdshader")
	var ok := src.contains("0 body, 1 fin, 2 jaw, 3 wing, 4 bill, 5 paint,") and src.contains("6 lamp, 7 deck, 8 metal")
	ok = ok and SeaLifeMesh.P_FIN == 1 and SeaLifeMesh.P_JAW == 2 and SeaLifeMesh.P_WING == 3 and SeaLifeMesh.P_LAMP == 6 and SeaLifeMesh.P_DECK == 7
	_t._check(ok, "sea life: sea_life.gdshader's part codes are SeaLifeMesh's")
	_t._check(src.contains("kind == 2 && part == 3.0") and src.contains("part == 2.0") and src.contains("part == 6.0"), "sea life: the shader folds wings, opens jaws and lights lamps by those codes")


func _sounds() -> void:
	for name in ["bark", "splash", "plunge", "puff", "blow"]:
		var s := SeaSounds.stream(name)
		_t._check(s != null and s.data.size() > 2000, "sea life: the %s sound synthesises (%d bytes)" % [name, s.data.size() if s else 0])


func _events(sea: Node, plan: CityPlan) -> void:
	var pods := 0
	var lines := 0
	var whales := 0
	var same := true
	for n in 60:
		for k in range(-4, 4):
			var a: Dictionary = sea.call("pod", n, k)
			SeaLife.clear_cache()
			var b: Dictionary = sea.call("pod", n, k)
			same = same and a == b
			pods += 0 if a.is_empty() else 1
			lines += 0 if (sea.call("line", n, k) as Dictionary).is_empty() else 1
			whales += 0 if (sea.call("whale", n, k) as Dictionary).is_empty() else 1
	_t._check(same, "sea life: a pod is the same for the same window and stretch, every time")
	var total := 60.0 * 8.0
	_t._check(absf(pods / total - SeaLife.DOLPHIN_ODDS) < 0.1 and absf(lines / total - SeaLife.PELICAN_ODDS) < 0.1 and absf(whales / total - SeaLife.WHALE_ODDS) < 0.1,
		"sea life: the odds come out near their numbers (pods %.2f, lines %.2f, whales %.2f)" % [pods / total, lines / total, whales / total])
	# Another seed rolls other windows.
	var other := 0
	var sv: int = sea.get("seed_value")
	sea.set("seed_value", sv + 1)
	for n in 30:
		var e: Dictionary = sea.call("pod", n, 0)
		sea.set("seed_value", sv)
		var f: Dictionary = sea.call("pod", n, 0)
		sea.set("seed_value", sv + 1)
		other += 1 if e.is_empty() != f.is_empty() else 0
	sea.set("seed_value", sv)
	_t._check(other > 3, "sea life: another seed rolls other pods (%d of 30 windows differ)" % other)


## A pod somewhere along the coast: every dolphin is on open water past the break line; over its
## run some leap clear (the body's centre a metre up) and some only roll.
func _dolphins(sea: Node, plan: CityPlan) -> void:
	var m := plan.macro
	var found: Dictionary = {}
	for n in 80:
		for k in range(-6, 6):
			var e: Dictionary = sea.call("pod", n, k)
			if e.is_empty():
				continue
			if sea.call("_stretch_ok", float(e.zc), float(sea.call("_break_distance")) + float(e.s)):
				found = e
				break
		if not found.is_empty():
			break
	_t._check(not found.is_empty(), "sea life: a pod passes some open stretch of the coast")
	if found.is_empty():
		return
	var brk: float = sea.call("_break_distance")
	var offshore := true
	var top := -INF
	var rolls := 0
	var leaps := 0
	var splash: Array = []
	for i in 230:
		var t := float(found.t0) + float(i) * 0.5
		var ds: Array = sea.call("dolphins_at", found, t, splash)
		for d in ds:
			var p: Vector3 = d.pos
			offshore = offshore and m.zone_at(Vector2(p.x, p.z)) == MacroMap.Zone.OCEAN and m.coast_x(p.z) - p.x > brk + 15.0
			var sy: float = sea.call("sea_y", Vector2(p.x, p.z))
			top = maxf(top, p.y - sy)
			if p.y - sy > 0.6:
				leaps += 1
			elif p.y - sy > -0.4:
				rolls += 1
	_t._check(offshore, "sea life: every dolphin of the pod stays on open water beyond the break line (%.0f m)" % brk)
	_t._check(leaps > 0 and rolls > 0 and top > 0.8 and top < 2.6, "sea life: the pod leaps clear (top %.2f m, %d samples in the air) and rolls (%d)" % [top, leaps, rolls])
	_t._check(splash.size() > 0, "sea life: a dolphin breaking the water throws a splash (%d)" % splash.size())


func _pelicans(sea: Node, plan: CityPlan) -> void:
	var m := plan.macro
	var z := 0.0
	var at := Vector2(m.coast_x(z) - 90.0, z)
	sea.call("stage", "dive", at, 4.0)
	var forced: Array = sea.get("_forced")
	_t._check(forced.size() == 1, "sea life: a diving pelican line stages")
	if forced.is_empty():
		return
	var e: Dictionary = forced[0]
	var clock := SeaLife.clock
	var peak := -INF
	var sat := false
	var plunged := false
	var folded := false
	var splash: Array = []
	for i in 70:
		var t := clock + float(i) * 0.25
		var birds: Array = sea.call("pelicans_at", e, t, splash)
		var p: Dictionary = {}
		for bd in birds:
			if int(bd.j) == 1:
				p = bd
		if p.is_empty():
			continue
		var sy: float = sea.call("sea_y", Vector2(p.pos.x, p.pos.z))
		peak = maxf(peak, p.pos.y - sy)
		folded = folded or float(p.fold) > 0.9
		if float(p.fold) > 0.9 and absf(p.pos.y - sy) < 0.3 and float(p.amp) == 0.0:
			sat = true
	for s in splash:
		plunged = plunged or float(s.kind) == SeaLife.SPRAY_PLUNGE
	_t._check(peak > 8.0 and peak < 11.0, "sea life: the diving pelican climbs to ~9 m (%.1f m)" % peak)
	_t._check(folded and plunged, "sea life: it folds its wings and plunges with a splash")
	_t._check(sat, "sea life: then it sits on the water, wings folded")
	sea.call("clear_stage")


func _whale(sea: Node, plan: CityPlan) -> void:
	var m := plan.macro
	var at := Vector2(m.coast_x(0.0) - 900.0, 0.0)
	sea.call("stage", "whale", at, 0.0)
	var e: Dictionary = (sea.get("_forced") as Array)[0]
	var blows := 0
	var lift := 0.0
	var seen_back := false
	var prev := -INF
	for i in 300:
		var t := SeaLife.clock + float(i) * 0.5
		var splash: Array = []
		var w: Array = sea.call("whale_at", e, t, splash)
		for s in splash:
			if float(s.kind) == SeaLife.SPRAY_BLOW and float(s.age) < 0.5 and t - prev > 5.0:
				blows += 1
				prev = t
		for d in w:
			lift = maxf(lift, float(d.lift))
			seen_back = seen_back or (d.pos as Vector3).y > -2.0
	_t._check(blows == SeaLife.WHALE_BLOWS, "sea life: the whale blows %d times, %.0f s apart (%d)" % [SeaLife.WHALE_BLOWS, SeaLife.WHALE_GAP, blows])
	_t._check(seen_back and lift > 0.8, "sea life: its back rolls through the surface and its flukes lift on the last dive (%.2f)" % lift)
	sea.call("clear_stage")


func _buoys(sea: Node, plan: CityPlan) -> void:
	var m := plan.macro
	var list: Array = sea.call("buoys")
	_t._check(list.size() >= 1, "sea life: at least one harbour buoy is on open water (%d)" % list.size())
	if list.is_empty():
		return
	var ship := Vector2(3065.0, 6541.0)
	var b = list[0]
	var ok := true
	for bb in list:
		ok = ok and m.zone_at(bb.at) == MacroMap.Zone.OCEAN and (bb.at as Vector2).distance_to(ship) > 150.0
	_t._check(ok, "sea life: every buoy floats on open water clear of the cargo ship")
	_t._check(b.lions >= 2 and b.lions <= SeaLife.MAX_LIONS, "sea life: %d sea lions are hauled out on the buoy" % b.lions)
	var t := SeaLife.clock
	var lions: Array = sea.call("lions_at", b, t)
	var on_deck: bool = lions.size() == int(b.lions)
	var bx: Transform3D = sea.call("buoy_xform", b, t)
	for l in lions:
		var local: Vector3 = bx.affine_inverse() * (l.xf as Transform3D).origin
		on_deck = on_deck and Vector2(local.x, local.z).length() < SeaLifeMesh.BUOY_DECK_R and absf(local.y - SeaLifeMesh.BUOY_DECK_Y) < 0.05
	_t._check(on_deck, "sea life: every sea lion lies on the deck, inside its rim")
	# Barks: over a few minutes a bout comes round, and the barker's jaw opens.
	var sounds: Array = []
	var opened := 0.0
	var tp := t
	for i in 600:
		var tt := t + float(i) * 0.25
		for l in sea.call("lions_at", b, tt, [], sounds, tp):
			opened = maxf(opened, float(l.bark))
		tp = tt
	var nb := 0
	for s in sounds:
		nb += 1 if s.name == "bark" else 0
	_t._check(nb >= 6 and opened > 0.8, "sea life: the sea lions bark (%d barks in 150 s, jaw %.2f)" % [nb, opened])
	# A blast nearby sends them in; they come back.
	sea.call("startle_world", b.at, 40.0)
	var gone: Array = sea.call("lions_at", b, SeaLife.clock + 5.0)
	var back: Array = sea.call("lions_at", b, b.back_at + 20.0)
	_t._check(gone.is_empty() and back.size() == b.lions, "sea life: startled they go in (%d left), and haul out again (%d)" % [gone.size(), back.size()])
	b.scared_at = -1e9
	b.back_at = -1e9


## Staged in front of the camera, a pod is drawn: the dolphin batches carry instances.
func _draw(sea: Node, plan: CityPlan) -> void:
	var cam := _tree.root.get_camera_3d()
	if cam == null:
		_t._check(false, "sea life: a camera to draw for")
		return
	var eye := WorldState.to_world(cam.global_position)
	var m := plan.macro
	var at := Vector2(m.coast_x(eye.z) - 150.0, eye.z)
	sea.call("stage", "dolphin", at, 0.0)
	sea.call("advance", 0.01)
	await _tree.process_frame
	var drawn: Dictionary = sea.get("drawn")
	var n := int(drawn.get("dolphin:0", 0)) + int(drawn.get("dolphin:1", 0))
	var far := eye.distance_to(Vector3(at.x, 0.0, at.y)) > 1100.0
	_t._check(n > 0 or far, "sea life: a staged pod is drawn (%d dolphins; %.0f m off)" % [n, eye.distance_to(Vector3(at.x, 0.0, at.y))])
	sea.call("clear_stage")
