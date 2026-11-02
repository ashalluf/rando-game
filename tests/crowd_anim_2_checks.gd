extends RefCounted
## The crowd's walks (crowd-anim-2, CrowdGait) for tests/smoke_test.gd: every rig carries the
## gait library with each clip's measured ground speed; the gait is a pure hash of the seed and the
## build and spreads over the gaits; a walker plays its gait's clip at the rate its ground speed
## asks for (no foot sliding: the planted toe is measured in the world while it walks), within
## the cadence band; it banks into a turn and straightens out again; and nothing the seed
## decides outside the walk moves (model, look, route, shirt) with CROWD_ANIM_2 on or off.
## One walker at a time on the spawn block's pavement, staged from scratch (no state from an
## earlier file is leaned on).

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var was_onlookers := Onlookers.enabled
	var was_rain := RainCrowd.forced
	Onlookers.enabled = false
	RainCrowd.forced = 0.0
	_library_checks()
	_pick_checks()
	await _walker_checks(city)
	Onlookers.enabled = was_onlookers
	RainCrowd.forced = was_rain
	CrowdGait.forced = ""


func _library_checks() -> void:
	var missing: Array = []
	var bad: Array = []
	var lo := INF
	var hi := 0.0
	for path: String in Pedestrian.MODELS:
		var lib := CrowdGait.library(path)
		if lib == null:
			missing.append(path.get_file())
			continue
		for g: String in CrowdGait.GAITS:
			if g == "classic":
				continue
			if not lib.has_animation(g):
				bad.append("%s:%s" % [path.get_file(), g])
				continue
			var gs := float(lib.get_animation(g).get_meta("ground_speed", 0.0))
			lo = minf(lo, gs)
			hi = maxf(hi, gs)
			if gs < 0.4 or gs > 1.6:
				bad.append("%s:%s %.2f" % [path.get_file(), g, gs])
		if not lib.has_animation("idle") or lib.get_animation("idle").length < 4.0:
			bad.append("%s:idle" % path.get_file())
	_check(missing.is_empty() and bad.is_empty(),
		"every crowd rig has the gait library, six walks with a measured ground speed (%.2f-%.2f m/s) and a long idle (missing %s, bad %s)" % [lo, hi, missing, bad])
	# The styles really differ: on one rig an amble covers less ground per cycle than a brisk walk.
	var lib0 := CrowdGait.library(Pedestrian.MODELS[0])
	if lib0 != null:
		var amble := float(lib0.get_animation("amble").get_meta("ground_speed", 0.0))
		var brisk := float(lib0.get_animation("brisk").get_meta("ground_speed", 0.0))
		_check(brisk > amble * 1.2, "a brisk step covers more ground than an amble (%.2f vs %.2f m/s a cycle)" % [brisk, amble])


func _pick_checks() -> void:
	var lib := CrowdGait.library(Pedestrian.MODELS[0])
	var heavy := CrowdGait.library("res://assets/models/crowd_q.glb") # weight 1.0
	var slim := CrowdGait.library("res://assets/models/crowd_i.glb") # weight 0.32
	if lib == null or heavy == null or slim == null:
		_check(false, "the gait libraries load for the pick checks")
		return
	var seen := {}
	var same := true
	var heavy_n := 0
	var slim_light := 0
	var avg_light := 0
	for i in 400:
		var g := CrowdGait.pick(1000 + i, lib, 1.0)
		seen[g] = int(seen.get(g, 0)) + 1
		same = same and g == CrowdGait.pick(1000 + i, lib, 1.0)
		heavy_n += 1 if CrowdGait.pick(1000 + i, heavy, 1.0) == "heavy" else 0
		slim_light += 1 if CrowdGait.pick(1000 + i, slim, 1.0) == "light" else 0
		avg_light += 1 if g == "light" else 0
	var biggest := 0
	for k: String in seen:
		biggest = maxi(biggest, int(seen[k]))
	_check(same and seen.size() >= 6 and biggest < 160,
		"the gait is a pure hash and spreads over the gaits (%s)" % [seen])
	_check(heavy_n > 240 and slim_light > avg_light * 2,
		"the build steers it: a heavy body walks heavy %d / 400, a slim one light %d / 400 (an average one %d)" % [heavy_n, slim_light, avg_light])


func _walker_checks(city: Node3D) -> void:
	# The streaming settled first: a chunk still due to be replaced (an LOD one the FULL ring is
	# building over, after the reset brought the player home) was freed under the check (gate run
	# 2525: SCRIPT ERROR, the chunk "previously freed" in _walk_check).
	city.update_streaming(true)
	await _tree.process_frame
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null and int(chunk.get("level")) == CityChunk.Level.FULL, "the spawn block's chunk is loaded in full for the gait checks")
	if chunk == null:
		return
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	# No drift: the same seed with the gaits off and on is the same person, on the same route.
	var sig: Array = []
	for on in [0, 1]:
		CrowdGait._enabled = on
		var p := _make(chunk, rect, 4243)
		await _ticks(2)
		sig.append([p._model_path, p._look, p.shirt, p._target, p._carry, p._jogger, p._style.randi(), p._rng.randi()])
		p.queue_free()
	CrowdGait._enabled = -1
	_check(sig[0] == sig[1], "the gaits move nothing else the seed decides (off %s / on %s)" % [sig[0], sig[1]])
	if not CrowdGait.enabled():
		return
	for g: String in ["heavy", "brisk", "amble"]:
		if not is_instance_valid(chunk):
			_check(false, "the spawn block's chunk lasts the gait checks")
			break
		await _walk_check(chunk, rect, g)


## One walker of gait `g` along the north pavement: clip, rate, the planted toe, the turn lean.
func _walk_check(chunk: Node3D, rect: Rect2, g: String) -> void:
	CrowdGait.forced = g
	var p := _make(chunk, rect, 5150 + g.length())
	CrowdGait.forced = ""
	var z := rect.position.y + 2.0
	var a := Vector2(rect.position.x + 6.0, z)
	var b := Vector2(minf(rect.position.x + 60.0, rect.end.x - 6.0), z)
	p.position = Vector3(a.x, chunk.ground_y(a.x, a.y) + 0.1, a.y)
	await _ticks(2)
	p._visual.rotation.y = -PI * 0.5 # facing east
	p._faced = true
	_check(p.gait == g and p._walk_clip == "gait/" + g, "a %s walker plays its gait's clip (%s, %s)" % [g, p.gait, p._walk_clip])
	var sk: Skeleton3D = p._head_skel
	var toes := [sk.find_bone("LeftToeBase"), sk.find_bone("RightToeBase")] if sk else []
	var slide := 0.0
	var planted := 0
	var prev := [Vector3.INF, Vector3.INF]
	var low := INF
	for i in 150:
		if not is_instance_valid(p) or not is_instance_valid(chunk):
			_check(false, "the %s walker and its chunk last the walk" % g)
			return
		_steer(p, b)
		await _tree.physics_frame
		if sk == null or i < 70:
			continue
		var y := [0.0, 0.0]
		var at := [Vector3.ZERO, Vector3.ZERO]
		for s in 2:
			at[s] = sk.global_transform * sk.get_bone_global_pose(toes[s]).origin
			y[s] = (at[s] as Vector3).y
			low = minf(low, y[s])
		for s in 2:
			if prev[s] != Vector3.INF and float(y[s]) < low + 0.02 and float(y[s]) <= float(y[1 - s]):
				var d: Vector3 = at[s] - prev[s]
				slide += Vector2(d.x, d.z).length()
				planted += 1
			prev[s] = at[s]
	var rate: float = p._anim.speed_scale if p._anim else 0.0
	var matched := rate * p._walk_clip_speed * p._stride
	var step_speed := p._walk_clip_speed * p._stride
	_check(p._clip == p._walk_clip and absf(matched - p._speed) < 0.05 and rate <= CrowdGait.CADENCE.y + 0.01,
		"a %s walk runs at the rate its ground speed asks for (clip covers %.2f m/s, body %.2f, rate %.2f)" % [g, matched, p._speed, rate])
	var slide_speed := slide / maxf(planted, 1) * Engine.physics_ticks_per_second
	_check(sk == null or (planted > 20 and slide_speed < 0.3 * p._speed),
		"a %s walker's planted foot stays planted (slides %.2f m/s at %.2f m/s, %d planted ticks)" % [g, slide_speed, p._speed, planted])
	_check(p.walk_speed >= step_speed * CrowdGait.CADENCE.x - 0.01 and p.walk_speed <= step_speed * CrowdGait.CADENCE.y + 0.01,
		"a %s walker's pace keeps a walker's cadence (%.2f m/s, step %.2f m/s)" % [g, p.walk_speed, step_speed])
	if g == "brisk":
		# A bend to the north-east and back: it banks into it and straightens out.
		var bank := 0.0
		var here := Vector2(p.position.x, p.position.z)
		for i in 40:
			_steer(p, here + Vector2(30.0, -30.0))
			await _tree.physics_frame
			bank = maxf(bank, absf(p._visual.rotation.z))
		for i in 120:
			_steer(p, Vector2(p.position.x + 40.0, p.position.z))
			await _tree.physics_frame
		# In a busy shard CrowdFlow can sidestep it round someone else on the straight: give it
		# up to four more seconds of straight road to come upright.
		for i in 240:
			if absf(p._visual.rotation.z) < 0.01:
				break
			_steer(p, Vector2(p.position.x + 40.0, p.position.z))
			await _tree.physics_frame
		_check(bank > 0.01 and bank <= CrowdGait.TURN_LEAN_MAX + 0.001 and absf(p._visual.rotation.z) < 0.01,
			"a walker banks into a bend and straightens after it (%.1f degrees, then %.1f)" % [rad_to_deg(bank), rad_to_deg(p._visual.rotation.z)])
	p.queue_free()


func _make(chunk: Node3D, rect: Rect2, seed_value: int) -> Pedestrian:
	var p := Pedestrian.new()
	p.set_meta("no_trim", true) # never trimmed or borrowed by the live crowd systems
	p.setup(rect, 4.0, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_range = 0.0
	p.position = Vector3(rect.position.x + 6.0, chunk.ground_y(rect.position.x + 6.0, rect.position.y + 2.0) + 0.1, rect.position.y + 2.0)
	chunk.add_child(p)
	return p


func _steer(ped: Pedestrian, target: Vector2) -> void:
	ped._target = target
	ped._route = PackedVector2Array()
	ped._route_pending = false


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
