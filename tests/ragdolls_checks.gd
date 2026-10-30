extends RefCounted
## Jointed ragdoll checks for tests/smoke_test.gd (RagdollJoints): a person knocked down near the
## camera falls as eleven jointed parts, every one a direct child of the doll (so a round finds
## it), the joints hold while it tumbles, it comes to rest on the ground and on a car-high box
## (the props layer, a bonnet), it freezes back into ONE compound body holding its pose, a round
## into it still bleeds, a blast still tears limbs off, the cap and the range hold, and with the
## switch off the old single body comes back. Stages its own walkers on the spawn block; loaded at
## run time like the other crowd checks, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check_pure()
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	if chunk == null and t.has_method("stage_home"):
		await t.stage_home()
		chunk = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the ragdoll checks")
	if chunk == null:
		return
	var was := [RagdollJoints.enabled, RagdollJoints.joint_range, RagdollJoints.max_active]
	RagdollJoints.enabled = true
	RagdollJoints.joint_range = 100000.0 # wherever the camera stands by now
	await _check_fall(city, chunk)
	await _check_bonnet(city, chunk)
	await _check_gibs(city, chunk)
	await _check_cap_and_range(city, chunk)
	RagdollJoints.enabled = was[0]
	RagdollJoints.joint_range = was[1]
	RagdollJoints.max_active = was[2]
	for n in _made:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await _ticks(2)


func _check_pure() -> void:
	var names := {}
	var order_ok := true
	var share := 0.0
	for i in RagdollJoints.PARTS.size():
		var p: Dictionary = RagdollJoints.PARTS[i]
		if int(p.parent) >= i:
			order_ok = false
		names[p.name] = true
		share += float(p.share)
	_check(order_ok and int(RagdollJoints.PARTS[0].parent) == -1, "the ragdoll's parts list every parent before its children, the pelvis first")
	_check(absf(share - 1.0) < 0.01, "the parts' mass shares add up to the whole doll (%.3f)" % share)
	var limbs_ok: bool = RagdollJoints.LIMB_PARTS.keys().size() == Ragdoll.LIMBS.keys().size()
	for limb: String in RagdollJoints.LIMB_PARTS:
		limbs_ok = limbs_ok and Ragdoll.LIMBS.has(limb)
		for n: String in RagdollJoints.LIMB_PARTS[limb]:
			limbs_ok = limbs_ok and names.has(n)
	_check(limbs_ok, "every limb a blast tears off names the ragdoll parts it takes")


## A walker on the spawn block's pavement, ready to knock.
func _walker(city: Node3D, chunk: Node3D, along: float, seed: int) -> Pedestrian:
	var rect: Rect2 = city.plan.block(0, 0).rect
	var p := Pedestrian.new()
	p.setup(rect, city.plan.sidewalk_width, seed)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_chance = 0.0
	p.life_spawn_chance = 0.0
	p.set_meta("no_trim", true)
	var at := Vector2(rect.position.x + 4.0 + along, rect.position.y + 2.0)
	p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.05, at.y)
	chunk.add_child(p)
	_made.append(p)
	return p


func _doll_of(p: Pedestrian) -> Ragdoll:
	var d: Ragdoll = p._doll
	if d != null:
		_made.append(d)
	return d


## A floor of the checks' own, 30 m over the junction north-west of the spawn block (nothing an
## earlier check left on the street can be under the doll: CI 378 found one lying 0.6 m up on
## something), `slot` floors apart. Returns its top's centre.
func _floor(city: Node3D, chunk: Node3D, slot: int) -> Vector3:
	var rect: Rect2 = city.plan.block(0, 0).rect
	var at := Vector2(rect.position.x - 6.0 + float(slot) * 14.0, rect.position.y - 6.0)
	var top: float = chunk.ground_y(at.x, at.y) + 30.0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12.0, 1.0, 12.0)
	cs.shape = bs
	body.add_child(cs)
	chunk.add_child(body)
	_made.append(body)
	# Chunk space is the walkers' (true world in the chunk's frame), as _walker places them.
	body.position = Vector3(at.x, top - 0.5, at.y)
	return chunk.to_global(Vector3(at.x, top, at.y))


## A doll made the way Pedestrian.knock() makes one, standing on `at` (world) and flung.
func _doll_at(chunk: Node3D, at: Vector3, yaw: float, impulse: Vector3) -> Ragdoll:
	var d := Ragdoll.new()
	chunk.add_child(d)
	d.global_position = at
	d.rotation.y = yaw
	var models: Array = Pedestrian.MODELS
	if not d.build_from_rig(models[0], 0):
		d.build(Color.GRAY, Color.DIM_GRAY, Color.BURLYWOOD)
	PhysicsBudget.register_debris(d)
	d.fling(impulse)
	_made.append(d)
	return d


func _check_fall(city: Node3D, chunk: Node3D) -> void:
	# The knock path: a walker knocked down near the camera becomes a jointed doll.
	var p := _walker(city, chunk, 6.0, 7301)
	await _ticks(3)
	p.knock(Vector3(1.0, 1.5, 2.5) * 2.0)
	var kd := _doll_of(p)
	_check(kd != null and kd._joints != null, "a person knocked down near the camera falls as a jointed ragdoll")
	if kd != null:
		kd.queue_free()
	# The fall itself, on a clear floor.
	var ground := _floor(city, chunk, 0)
	await _ticks(2)
	var doll := _doll_at(chunk, ground + Vector3.UP * 0.05, 0.4, Vector3(1.0, 1.5, 2.5) * 2.0)
	_check(doll._joints != null, "a doll made near the camera is jointed")
	if doll._joints == null:
		return
	var j: RagdollJoints = doll._joints
	_check(doll.bodies.size() == RagdollJoints.PARTS.size() and doll.bodies[0] == j.parts["pelvis"],
		"the doll is %d bodies, the pelvis first (%d)" % [RagdollJoints.PARTS.size(), doll.bodies.size()])
	var direct := doll.bodies.all(func(b): return (b as Node).get_parent() == doll)
	_check(direct, "every part is a direct child of the doll, so a round or a pellet finds the body it hit")
	_check(doll.find_child("RagdollPose", true, false) is RagdollPose, "a RagdollPose poses the skeleton from the parts")
	var worst := 0.0
	var froze_at := -1
	for i in int((RagdollJoints.settle_max + 2.0) * 60.0):
		await _ticks(1)
		if not is_instance_valid(doll):
			break
		if not j.frozen:
			worst = maxf(worst, j.gap())
		elif froze_at < 0:
			froze_at = i
			break
	_check(is_instance_valid(doll), "the doll lasts until it settles")
	if not is_instance_valid(doll):
		return
	_check(worst < 0.12, "the joints hold while the doll tumbles (worst gap %.3f m)" % worst)
	_check(froze_at >= 0, "the doll freezes into one body once it settles (after %.1f s)" % (froze_at / 60.0))
	_check(doll.bodies.size() == 1 and doll.bodies.all(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion()),
		"a frozen doll is ONE live body again (%d)" % doll.bodies.size())
	var shapes := doll.bodies[0].get_children().filter(func(c): return c is CollisionShape3D).size()
	_check(shapes >= RagdollJoints.PARTS.size(), "the frozen body keeps every part's shape where it fell (%d shapes)" % shapes)
	await _ticks(1)
	var leftover := doll.get_children().filter(func(c): return (c is RigidBody3D or c is Joint3D) and not c.is_queued_for_deletion()).size()
	_check(leftover == 1, "the limb bodies and joints are gone once frozen (%d bodies and joints left)" % leftover)
	# Lying down on its floor: the hips and the head within knee height of it.
	var skel := doll._skeleton()
	var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin
	var hips := doll._pelvis()
	_check(hips.y - ground.y < 0.6 and head.y - ground.y < 0.7, "the body lies on the ground (hips %.2f m, head %.2f m up)" % [hips.y - ground.y, head.y - ground.y])
	_check(head.distance_to(hips) > 0.35 and head.distance_to(hips) < 1.1, "the posed skeleton holds together (head %.2f m from the hips)" % head.distance_to(hips))
	# A round into the frozen body still bleeds, through the body it hits.
	var from := hips + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, hips + Vector3.DOWN * 0.3, 4)
	var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
	var bled := false
	if hit:
		bled = WeaponFX.bullet_wound(doll, hit, Vector3.DOWN, 1.0) and doll.bleed > 0.0
	_check(bled, "a round into a frozen doll finds it and it bleeds")


## Dropped onto a car-high box on the props layer (a bonnet) on a clear floor: it rests on top.
func _check_bonnet(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 1)
	var top := ground.y + 0.9
	var box := StaticBody3D.new()
	box.collision_layer = 4
	box.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 0.9, 2.4)
	cs.shape = bs
	box.add_child(cs)
	chunk.add_child(box)
	_made.append(box)
	box.global_position = ground + Vector3(0.0, 0.45, 0.0)
	await _ticks(2)
	var doll := _doll_at(chunk, ground + Vector3.UP * 1.2, 0.0, Vector3(0.0, 0.5, 0.0))
	_check(doll._joints != null, "a doll dropped on a bonnet is jointed")
	if doll._joints == null:
		return
	for i in int((RagdollJoints.settle_max + 2.0) * 60.0):
		await _ticks(1)
		if not is_instance_valid(doll) or doll._joints.frozen:
			break
	var hips := doll._pelvis() if is_instance_valid(doll) else Vector3.ZERO
	_check(is_instance_valid(doll) and hips.y > top - 0.15, "a doll comes to rest on a car-high box, not through it (hips %.2f over its top)" % (hips.y - top))


## A close blast: limbs torn off take their parts and joints with them, and the rest still settles.
func _check_gibs(city: Node3D, chunk: Node3D) -> void:
	var p := _walker(city, chunk, 22.0, 7303)
	await _ticks(3)
	p.knock(Vector3(0.0, 3.0, 2.0) * 2.0, 2)
	var doll := _doll_of(p)
	if doll == null or doll._joints == null:
		_check(false, "a gibbed doll is jointed")
		return
	var torn := doll._hider.bones.size() if doll._hider else 0
	_check(torn >= 1 and doll.bodies.size() < RagdollJoints.PARTS.size(), "torn-off limbs take their ragdoll parts with them (%d torn, %d parts left)" % [torn, doll.bodies.size()])
	var ok := true
	for i in int((RagdollJoints.settle_max + 2.0) * 60.0):
		await _ticks(1)
		if not is_instance_valid(doll):
			ok = false
			break
		if doll._joints.frozen:
			break
	_check(ok and doll._joints.frozen and doll.bodies.size() == 1, "a gibbed doll still settles into one body")


## The cap: at most max_active jointed at once (the oldest freezes); past the range, the old body;
## with the switch off, the old body.
func _check_cap_and_range(city: Node3D, chunk: Node3D) -> void:
	RagdollJoints.max_active = 2
	var dolls: Array = []
	for i in 4:
		var p := _walker(city, chunk, 30.0 + i * 3.0, 7310 + i)
		await _ticks(2)
		p.knock(Vector3(0.0, 1.0, 1.0) * 2.0)
		dolls.append(_doll_of(p))
	var jointed := dolls.filter(func(d): return d != null and d._joints != null and not d._joints.frozen).size()
	_check(RagdollJoints.active_count() <= 2 and jointed <= 2, "no more than max_active dolls are jointed at once (%d)" % jointed)
	_check(dolls[3] != null and dolls[3]._joints != null and not dolls[3]._joints.frozen, "the newest doll gets the joints and the oldest freezes for it")
	var stale := 0
	for d in dolls:
		if d != null and d._joints != null and d._joints.frozen:
			for b in d.bodies:
				if not is_instance_valid(b) or (b as Node).is_queued_for_deletion():
					stale += 1
	_check(stale == 0, "a doll frozen to make room lists only its live body (%d freed bodies listed)" % stale)
	RagdollJoints.joint_range = 0.0
	var far := _walker(city, chunk, 44.0, 7320)
	await _ticks(2)
	far.knock(Vector3(0.0, 1.0, 1.0) * 2.0)
	var fd := _doll_of(far)
	_check(fd != null and fd._joints == null and fd.bodies.size() == 1, "a doll out of the joints' range is the old single body")
	RagdollJoints.joint_range = 100000.0
	RagdollJoints.enabled = false
	var off := _walker(city, chunk, 48.0, 7321)
	await _ticks(2)
	off.knock(Vector3(0.0, 1.0, 1.0) * 2.0)
	var od := _doll_of(off)
	_check(od != null and od._joints == null and od.bodies.size() == 1, "RAGDOLLS=0 keeps the old single body")
	RagdollJoints.enabled = true


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
