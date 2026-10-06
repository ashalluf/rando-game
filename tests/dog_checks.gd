extends RefCounted
## The city's dogs (DogMesh, DogRig, Dog, CrowdDog, YardDog, DogYard) for tests/smoke_test.gd.
## Loaded at run time (not named there), so it compiles after the autoloads. Checks: every breed's
## three levels build inside their triangle budgets, skinned to the 28-bone skeleton, at the
## breed's real size; every coat and sound loads; the rig keeps its paws on the ground standing,
## lifts and swings them walking, drops its haunches sitting, and never goes NaN; a dog walker's
## dog walks at its owner's left as a sibling of the owner, follows it, and is on its lead; hit or
## shot it yelps and bolts with no blood; its owner going down sets it running rather than freeing
## it; a gunshot sets it barking; the yard dogs' share is a pure hash, and a yard dog runs to its
## fence and barks at the player, cowers from a gun and never leaves its yard.

var _t: Node
var _tree: SceneTree

## [skin, shells] triangle budgets per level.
const BUDGET := [[8000, 70000], [3000, 13000], [1100, 0]]


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_meshes()
	_assets()
	await _rig()
	# Everything is staged beside wherever the player stands now, in the chunk under him: moving
	# the player would stream and re-centre the city under the checks that come after these.
	var player: Node3D = _tree.get_first_node_in_group("player")
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var here: Vector3 = ws.call("to_world", player.global_position)
	var bi: Vector2i = city.plan.block_index_at(Vector2(here.x, here.z))
	var chunk: Node3D = city.chunks.get(bi)
	_check(chunk != null, "dogs: the chunk under the player is loaded")
	if chunk == null:
		return
	await _crowd_dog(city, chunk)
	await _yard(city, chunk)


func _meshes() -> void:
	var over: Array = []
	var bad_skin := 0
	var bad_size: Array = []
	for name: String in DogMesh.BREEDS:
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
				# Real size: the top of the back at the withers, the body length.
				var b := DogMesh.breed(name)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var j := DogMesh.joints(name)
				var wz: float = (j["Chest"] as Vector3).z
				var top := 0.0
				var lo := INF
				var hi := -INF
				for v in verts:
					if absf(v.z - wz) < float(b.l) * 0.06 and absf(v.x) < float(b.cw) * 0.3:
						top = maxf(top, v.y)
					lo = minf(lo, v.y)
					hi = maxf(hi, v.y)
				if absf(top - float(b.h)) > float(b.h) * 0.12 or lo < -0.01 or lo > 0.02:
					bad_size.append("%s withers %.2f of %.2f, sole %.3f" % [name, top, float(b.h), lo])
	_check(over.is_empty(), "dogs: every breed's three levels are within budget (%s)" % ", ".join(over))
	_check(bad_skin == 0, "dogs: every vertex is skinned to the skeleton with weights summing to one (%d bad)" % bad_skin)
	_check(bad_size.is_empty(), "dogs: each breed stands at its real withers height on the ground (%s)" % "; ".join(bad_size))
	var odds := 0.0
	for row: Array in DogMesh.BREED_ODDS:
		odds += float(row[1])
	_check(absf(odds - 1.0) < 0.001 and DogMesh.BREED_ODDS.size() == DogMesh.BREEDS.size(), "dogs: the breed odds cover every breed and sum to one")


func _assets() -> void:
	var missing: Array = []
	for name: String in DogMesh.BREEDS:
		for row: Array in DogMesh.breed(name).looks:
			if not ResourceLoader.exists(DogMesh.TEXTURE_DIR + String(row[0]) + ".jpg"):
				missing.append(row[0])
	for f in ["bark_big_0", "bark_small_0", "dog_yelp_0"]:
		if not ResourceLoader.exists("res://assets/audio/%s.ogg" % f):
			missing.append(f)
	var sfx: Node = _tree.root.get_node("/root/Sfx")
	for n in ["bark_big", "bark_small", "dog_yelp"]:
		if not sfx.call("has", n):
			missing.append(n)
	_check(missing.is_empty(), "dogs: every coat and the barks and yelps load (%s)" % ",".join(missing))


func _rig() -> void:
	var holder := Node3D.new()
	_tree.root.add_child(holder)
	var rig := DogRig.make("shepherd", "shepherd", 3)
	holder.add_child(rig)
	await _tree.process_frame
	rig.force_level(0)
	var sk := rig.skeleton
	var paws: Array = []
	for leg: Array in DogMesh.B_LEGS:
		paws.append(leg[3])
	# Standing: every paw where it rests.
	for i in 30:
		rig.advance(1.0 / 30.0)
	var rest := DogMesh.rest_positions("shepherd")
	var off := 0.0
	for p: int in paws:
		off = maxf(off, sk.get_bone_global_pose(p).origin.distance_to(rest[p]))
	_check(off < 0.01, "dogs: standing, every paw is on its spot (%.3f m off)" % off)
	# Walking: over a stride each paw spends time down on the ground and lifts clear of it.
	rig.speed = 1.2
	var lo := [INF, INF, INF, INF]
	var hi := [-INF, -INF, -INF, -INF]
	var nan := false
	for i in 150:
		rig.advance(1.0 / 60.0)
		for k in 4:
			var y := sk.get_bone_global_pose(paws[k]).origin.y
			nan = nan or is_nan(y)
			lo[k] = minf(lo[k], y)
			hi[k] = maxf(hi[k], y)
	var ok := not nan
	for k in 4:
		ok = ok and absf(float(lo[k]) - rest[paws[k]].y) < 0.01 and float(hi[k]) - float(lo[k]) > 0.03
	_check(ok, "dogs: walking, every paw is planted and lifted in turn (%s .. %s)" % [str(lo), str(hi)])
	# Sitting: the haunches drop by a third or more, the front paws stay down.
	rig.speed = 0.0
	rig.sit = 1.0
	for i in 120:
		rig.advance(1.0 / 30.0)
	var pel := sk.get_bone_global_pose(DogMesh.B_PELVIS).origin.y
	var front := sk.get_bone_global_pose(paws[0]).origin.y
	_check(pel < rest[DogMesh.B_PELVIS].y * 0.66 and absf(front - rest[paws[0]].y) < 0.02,
		"dogs: sitting, the haunches drop (pelvis %.2f of %.2f) and the front paws stay down" % [pel, rest[DogMesh.B_PELVIS].y])
	holder.queue_free()
	await _tree.process_frame


func _crowd_dog(city: Node3D, chunk: Node3D) -> void:
	var plan: CityPlan = city.plan
	var player: Node3D = _tree.get_first_node_in_group("player")
	var me := chunk.to_local(player.global_position)
	var bi := plan.block_index_at(Vector2(me.x, me.z))
	var rect: Rect2 = plan.block(bi.x, bi.y).rect
	var x0 := me.x + 3.0
	var z := me.z + 3.0
	var p := Pedestrian.new()
	p.setup(rect, plan.sidewalk_width, 9150)
	p.jogger_share = Vector2.ZERO
	p.dog_share = Vector2.ONE
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_spawn_chance = 0.0
	p.life_range = 100000.0
	p.look_range = 100000.0
	p.position = Vector3(x0, chunk.ground_y(x0, z) + 0.1, z)
	# The crowd cap's trim must not free the walker under test (CityStreamer.trim_pedestrians()).
	p.set_meta("no_trim", true)
	chunk.add_child(p)
	await _ticks(40)
	var dog: CrowdDog = p._dog as CrowdDog
	_check(dog != null and is_instance_valid(dog) and dog.is_inside_tree() and dog.get_parent() == p.get_parent(),
		"dogs: a dog walker has a dog, a sibling of its owner under the chunk")
	if dog == null or not is_instance_valid(dog):
		p.queue_free()
		return
	var d := Vector2(dog.position.x - p.position.x, dog.position.z - p.position.z).length()
	_check(d < 1.6 and dog.is_in_group("dog"), "dogs: the dog walks at its owner's side (%.2f m)" % d)
	# Following: the owner walks on, the dog keeps up.
	var start := dog.position
	var owner_start := p.position
	await _ticks(90)
	var d2 := Vector2(dog.position.x - p.position.x, dog.position.z - p.position.z).length()
	var walked := p.position.distance_to(owner_start)
	_check(d2 < 1.8 and (walked < 0.5 or dog.position.distance_to(start) > walked * 0.5),
		"dogs: the dog keeps up with its owner (%.2f m from it; owner walked %.2f m, dog %.2f m)" % [d2, walked, dog.position.distance_to(start)])
	# A round into it: no blood, a yelp, it bolts.
	var blood_before: Dictionary = WeaponFX.blood_counts()
	var shot := WeaponFX.bullet_wound(dog, {"collider": dog.hit_box, "position": dog.global_position + Vector3.UP * 0.3}, Vector3(1, 0, 0), 1.0, Vector3(14, 5, 0))
	await _ticks(30)
	var blood_after: Dictionary = WeaponFX.blood_counts()
	_check(shot and is_instance_valid(dog) and dog.fleeing and dog.hits_taken == 1, "dogs: a round into a dog sends it running")
	_check(blood_after.systems == blood_before.systems and blood_after.splats == blood_before.splats, "dogs: a shot dog does not bleed (no gore on animals)")
	if is_instance_valid(dog):
		dog.queue_free()
	p.queue_free()
	await _ticks(2)
	# A second walker: the owner goes down, the dog bolts (it is not freed with its owner).
	var q := Pedestrian.new()
	q.setup(rect, plan.sidewalk_width, 9177)
	q.jogger_share = Vector2.ZERO
	q.dog_share = Vector2.ONE
	q.pause_chance = 0.0
	q.cross_chance = 0.0
	q.life_spawn_chance = 0.0
	q.life_range = 100000.0
	q.look_range = 100000.0
	q.position = Vector3(x0 + 3.0, chunk.ground_y(x0 + 3.0, z) + 0.1, z)
	q.set_meta("no_trim", true)
	chunk.add_child(q)
	await _ticks(30)
	if not is_instance_valid(q):
		_check(false, "dogs: the second walker is still there after 30 ticks")
		return
	var dog2: CrowdDog = q._dog as CrowdDog
	if dog2 == null or not is_instance_valid(dog2):
		_check(false, "dogs: the second walker has a dog")
		return
	# A gunshot nearby: it barks with its tail tucked.
	Police.innocent = true
	Pedestrian.alarm(_tree, dog2.global_position + Vector3(4, 0, 0), 30.0, 0, true, "")
	Police.innocent = false
	await _ticks(10)
	_check(is_instance_valid(dog2) and (dog2._bark_left > 0 or dog2.rig.bark > 0.0 or dog2._fear_left > 0.0), "dogs: a gunshot nearby sets a lead dog barking")
	Police.innocent = true
	q.knock(Vector3(3, 2, 0))
	Police.innocent = false
	await _ticks(20)
	_check(is_instance_valid(dog2) and dog2.fleeing, "dogs: its owner knocked down, the dog bolts (and outlives its owner)")
	if is_instance_valid(dog2):
		var at := dog2.position
		await _ticks(30)
		_check(is_instance_valid(dog2) and dog2.position.distance_to(at) > 1.0, "dogs: a bolting dog runs")
		if is_instance_valid(dog2):
			dog2.queue_free()
	await _ticks(2)


func _yard(city: Node3D, chunk: Node3D) -> void:
	# The share is a pure hash: the same lots twice, about FRONT_ODDS of edged gardens.
	var plan: CityPlan = city.plan
	var frame := YardFill._frame(Rect2(0, 0, 14, 30), 0)
	var hits := 0
	var again := 0
	for k in 400:
		var lp := {"lot": {"seed": 1000 + k}, "frame": frame, "front": 6.0, "back": 20.0, "drive": Rect2(), "pieces": []}
		var a := DogYard.patch_for(plan, lp, true)
		var b := DogYard.patch_for(plan, lp, true)
		if not a.is_empty():
			hits += 1
		if a == b:
			again += 1
	_check(again == 400 and hits > 90 and hits < 190, "dogs: yard dogs are a pure hash share of the lots (%d of 400)" % hits)
	# A yard dog of our own on the spawn block: it runs to its fence and barks at the player.
	var player: Node3D = _tree.get_first_node_in_group("player")
	var me := chunk.to_local(player.global_position)
	var dog := YardDog.new()
	dog.chunk = chunk
	# The yard's fence 6 m from the player, the yard beyond it.
	var o := Vector2(me.x - 3.0, me.z + 6.0)
	dog.frame_o = o
	dog.frame_u = Vector2(1, 0)
	dog.frame_v = Vector2(0, 1)
	dog.patch = Rect2(0.5, 0.5, 6.0, 3.0)
	dog.fence_front = true
	dog.roll(4242, "terrier")
	chunk.add_child(dog)
	await _ticks(5)
	await _ticks(60)
	var uv := dog._to_uv(dog.position)
	_check(dog.state == YardDog.State.ALERT and uv.y < 1.6, "dogs: a yard dog runs to its fence when the player comes (v %.2f)" % uv.y)
	_check(dog._bark_left > 0 or dog._burst_left > 0.0 or dog.rig.bark > 0.0, "dogs: and barks at him")
	Police.innocent = true
	Pedestrian.alarm(_tree, player.global_position, 30.0, 0, true, "")
	Police.innocent = false
	await _ticks(60)
	uv = dog._to_uv(dog.position)
	var inside := dog.patch.grow(0.05).has_point(uv)
	_check(dog.state == YardDog.State.COWER and inside, "dogs: a gun sends it to the far corner of its yard (%s)" % str(uv))
	dog.hit_box.knock(Vector3(20, 6, 0))
	await _ticks(60)
	uv = dog._to_uv(dog.position)
	_check(is_instance_valid(dog) and dog.patch.grow(0.05).has_point(uv), "dogs: hit, a yard dog stays in its yard (%s)" % str(uv))
	dog.queue_free()
	await _ticks(2)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
