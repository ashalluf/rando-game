extends RefCounted
## The urban wildlife (WildSpecies, WildAnimal, Wildlife) for tests/smoke_test.gd. Loaded at run
## time (not named there), so it compiles after the autoloads. Checks: every species' three levels
## build inside the dogs' budgets, skinned, standing at the species' real withers height on the
## ground; every coat loads; the dogs' breeds and odds are untouched by the hook; the antlers
## build; the hours (coyotes at night, deer at dawn, raccoons deep in the night, squirrels by day)
## and the cells' plans are pure and keep to them; animals put down beside the player stand on the
## ground; one flushes and runs off when the player comes close, one bolts at a gunshot (Dog's
## startle), one hit by a round runs off with no blood, ragdoll or body left; a bolted animal is
## gone once it has run its course; the survey keeps to its cap and its distance.

var _t: Node
var _tree: SceneTree

const BUDGET := [[8000, 70000], [3000, 13000], [1100, 0]]


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_meshes()
	_hours(city)
	await _live(city)


func _meshes() -> void:
	var over: Array = []
	var bad_skin := 0
	var bad_size: Array = []
	for name: String in WildSpecies.NAMES:
		var b := DogMesh.breed(name)
		_check(b == WildSpecies.SPECIES[name], "wildlife: DogMesh.breed() finds the %s" % name)
		for lv in 3:
			var tc := DogMesh.triangle_count(name, lv)
			var bud: Array = BUDGET[lv]
			if tc.x > int(bud[0]) or tc.y > int(bud[1]) or tc.x < 300:
				over.append("%s/%d %d+%d" % [name, lv, tc.x, tc.y])
			var m: ArrayMesh = DogMesh.meshes(name, lv)[0]
			var arr := m.surface_get_arrays(0)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for i in range(0, bones.size(), 4):
				var s := w[i] + w[i + 1] + w[i + 2] + w[i + 3]
				if absf(s - 1.0) > 0.01 or bones[i] < 0 or bones[i] >= DogMesh.BONES.size():
					bad_skin += 1
			if lv == 0:
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var j := DogMesh.joints(name)
				var wz: float = (j["Chest"] as Vector3).z
				var top := 0.0
				var lo := INF
				for v in verts:
					if absf(v.z - wz) < float(b.l) * 0.06 and absf(v.x) < float(b.cw) * 0.3:
						top = maxf(top, v.y)
					lo = minf(lo, v.y)
				if absf(top - float(b.h)) > float(b.h) * 0.15 or lo < -0.01 or lo > 0.02:
					bad_size.append("%s withers %.3f of %.3f, sole %.3f" % [name, top, float(b.h), lo])
		for row: Array in b.looks:
			var path := DogMesh.TEXTURE_DIR + String(row[0]) + ".jpg"
			_check(ResourceLoader.exists(path) and load(path) is Texture2D, "wildlife: the %s coat %s loads" % [name, row[0]])
	_check(over.is_empty(), "wildlife: every species' three levels are within the dogs' budgets (%s)" % ", ".join(over))
	_check(bad_skin == 0, "wildlife: every vertex is skinned with weights summing to one (%d bad)" % bad_skin)
	_check(bad_size.is_empty(), "wildlife: each species stands at its real withers height on the ground (%s)" % "; ".join(bad_size))
	# The dogs are untouched: their own table, their odds, no wild animal on a lead.
	_check(absf(float(DogMesh.breed("labrador").h) - 0.57) < 1e-4 and DogMesh.breed("nonsense") == DogMesh.BREEDS.labrador,
		"wildlife: the dogs' breeds and the fallback are unchanged")
	var wild_rolled := false
	for i in 200:
		if WildSpecies.has(DogMesh.pick_breed(float(i) / 200.0)):
			wild_rolled = true
	_check(not wild_rolled, "wildlife: the crowd's dog breeds never roll a wild animal")
	var tris := 0
	for pts in [2, 3, 4]:
		var am := WildSpecies.antler_mesh(pts, 0)
		tris = am.surface_get_array_index_len(0) / 3 if am.surface_get_array_index_len(0) > 0 else am.surface_get_array_len(0) / 3
		_check(tris > 100 and tris < 8000, "wildlife: a %d-point buck's antlers build (%d triangles)" % [pts, tris])


func _hours(city: Node3D) -> void:
	var in_range := true
	for name: String in WildSpecies.NAMES:
		for i in 97:
			var a := WildSpecies.activity(name, float(i) * 0.25)
			if a < 0.0 or a > 1.0 or is_nan(a):
				in_range = false
	_check(in_range, "wildlife: every species' activity stays in 0..1 round the clock")
	_check(WildSpecies.activity("coyote", 22.0) > 0.6 and WildSpecies.activity("coyote", 13.0) < 0.1, "wildlife: coyotes are out at night, not at midday")
	_check(WildSpecies.activity("deer", 6.3) > 0.8 and WildSpecies.activity("deer", 13.0) < 0.1, "wildlife: deer graze at dawn, not at midday")
	_check(WildSpecies.activity("raccoon", 1.0) > 0.7 and WildSpecies.activity("raccoon", 12.0) == 0.0, "wildlife: raccoons are out deep in the night, never by day")
	_check(WildSpecies.activity("squirrel", 11.0) > 0.8 and WildSpecies.activity("squirrel", 23.0) == 0.0, "wildlife: squirrels are out by day, never at night")
	_check(WildSpecies.activity("rabbit", 6.5) > WildSpecies.activity("rabbit", 12.0), "wildlife: rabbits come out in the morning more than at midday")
	# The cells' plans: pure, and keeping to the hours and the habitats.
	var plan: CityPlan = city.plan
	var pure := true
	var bad: Array = []
	var seen := {}
	for hr in [6.5, 12.0, 22.0]:
		for cx in range(-14, 15):
			for cz in range(-14, 15):
				var a: Array = Wildlife.plan_cell(plan, cx * 3, cz * 3, hr)
				var b: Array = Wildlife.plan_cell(plan, cx * 3, cz * 3, hr)
				if str(a) != str(b):
					pure = false
				for s: Dictionary in a:
					seen[s.species] = true
					if WildSpecies.activity(s.species, hr) <= 0.0:
						bad.append("%s at %.1f" % [s.species, hr])
					if int(s.count) < 1 or not (s.species in WildSpecies.NAMES):
						bad.append("count %d %s" % [int(s.count), s.species])
					var z := plan.zone_at(s.at)
					if s.habitat == "hills" and z != MacroMap.Zone.HILLS:
						bad.append("hills spot off the hills")
					if s.habitat == "hills" and Wildlife._slope(plan, s.at) > Wildlife.MAX_SLOPE:
						bad.append("a hill animal on a cliff")
					if s.kind == "cross" and (s.route as Array).is_empty():
						bad.append("a crossing with no route")
	_check(pure, "wildlife: plan_cell() is pure (the same cell and hour plan the same animals)")
	_check(bad.is_empty(), "wildlife: planned animals keep to their hours and habitats (%s)" % ", ".join(bad.slice(0, 6)))
	_check(seen.size() >= 3, "wildlife: a sample of the map plans at least three species over the day (%s)" % ", ".join(seen.keys()))
	_check(Wildlife.on() == (OS.get_environment("WILDLIFE") != "0"), "wildlife: WILDLIFE=0 is the A/B switch")


func _live(city: Node3D) -> void:
	var wl: Wildlife = city.get_node_or_null("Wildlife")
	_check(wl != null, "wildlife: the city has its Wildlife node")
	if wl == null:
		return
	_check(not wl.enabled, "wildlife: the survey is off for the rest of the smoke test")
	var player: Node3D = _tree.get_first_node_in_group("player")
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var here: Vector3 = ws.call("to_world", player.global_position)
	var fwd := Vector3(1, 0, 0)
	# A squirrel well away, a deer, a raccoon: on the ground beside the player.
	var sq := wl.stage("squirrel", Vector2(here.x + 20.0, here.z + 3.0), 0.0, 11, true)
	var deer := wl.stage("deer", Vector2(here.x + 24.0, here.z - 6.0), 1.0, 12, true)
	var rac := wl.stage("raccoon", Vector2(here.x + 18.0, here.z + 10.0), 2.0, 13, true)
	await _ticks(6)
	for an: WildAnimal in [sq, deer, rac]:
		var p: Vector3 = ws.call("to_world", an.global_position)
		var gy: float = city.plan.height_at(Vector2(p.x, p.z))
		_check(absf(p.y - gy) < 2.5 and not is_nan(an.rig.skeleton.get_bone_global_pose(DogMesh.B_HEAD).origin.y),
			"wildlife: a staged %s stands on the ground (%.2f against %.2f) and its pose is sane" % [an.species, p.y, gy])
	_check(not sq.fleeing and not deer.fleeing and not rac.fleeing, "wildlife: calm animals stay put")
	# The player close: the squirrel flushes and runs off.
	sq.calm = false
	sq.global_position = player.global_position + fwd * 2.5
	var d0 := sq.global_position.distance_to(player.global_position)
	var f0 := WildAnimal.flushes
	await _until(func() -> bool: return sq.fleeing, 60)
	_check(sq.fleeing and WildAnimal.flushes > f0, "wildlife: a squirrel bolts when the player comes within its flush distance")
	await _ticks(40)
	if is_instance_valid(sq):
		_check(sq.global_position.distance_to(player.global_position) > d0 + 0.5, "wildlife: the bolting squirrel runs away from the player (%.1f -> %.1f m)" % [d0, sq.global_position.distance_to(player.global_position)])
	# A gunshot near the deer (Pedestrian.alarm calls Dog.startle_all).
	Dog.startle_all(_tree, deer.global_position + Vector3(4, 0, 0), 5.0)
	await _ticks(2)
	_check(deer.fleeing, "wildlife: a deer bolts at a gunshot near it")
	await _ticks(30)
	var lifted := false
	for i in 30:
		await _tree.physics_frame
		if is_instance_valid(deer) and deer.rig.position.y > 0.05:
			lifted = true
	_check(lifted, "wildlife: a fleeing mule deer stots (all four feet off the ground)")
	# A round into the raccoon: it runs, nothing bleeds, nobody becomes a body.
	var bodies := _tree.get_nodes_in_group("debris").size()
	var h0 := WildAnimal.hits
	rac.hit_box.shot(rac.global_position, Vector3(-1, 0, 0), Vector3(-4, 1, 0))
	await _ticks(3)
	_check(rac.hits_taken == 1 and WildAnimal.hits == h0 + 1 and rac.fleeing, "wildlife: a raccoon hit by a round is thrown and runs")
	_check(_tree.get_nodes_in_group("debris").size() <= bodies, "wildlife: a shot animal leaves no ragdoll or debris")
	# A bolted animal is gone once its run is over.
	rac.flee_min_seconds = 0.1
	rac.flee_max_seconds = 0.6
	var rac_id := rac.get_instance_id()
	await _until(func() -> bool: return not is_instance_id_valid(rac_id), 120)
	_check(not is_instance_id_valid(rac_id), "wildlife: a bolted animal is gone once it has run its course")
	for an in [sq, deer]:
		if is_instance_valid(an):
			an.queue_free()
	await _ticks(2)
	# The survey at night round the player: within its cap, none closer than min_spawn.
	Wildlife.force_hour = 22.0
	wl.survey()
	var n := 0
	var near := 0
	for an: WildAnimal in wl.animals():
		n += 1
		if an.global_position.distance_to(player.global_position) < wl.min_spawn - 6.0:
			near += 1
	_check(n <= wl.max_animals, "wildlife: the survey keeps to its cap (%d)" % n)
	_check(near == 0, "wildlife: nothing is put down right beside the player")
	for an: WildAnimal in wl.animals():
		an.queue_free()
	Wildlife.force_hour = -1.0
	await _ticks(2)


func _until(cond: Callable, max_ticks: int) -> void:
	for i in max_ticks:
		if cond.call():
			return
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
