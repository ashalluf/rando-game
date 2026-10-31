extends RefCounted
## Ragdoll feel checks for tests/smoke_test.gd (RagdollFeel, on RagdollJoints): a person shot by a
## rifle round staggers on their feet for a beat and then goes down along the round; a flung doll
## flies trunk first with its limbs trailing; a car's bumper makes it a car hit (the legs take the
## car's speed, the trunk is left behind, it rides up over the bonnet of a real car driven into
## it); a doll knocked at the top of a flight of steps rolls down them; RAGDOLL_FEEL=0 is the old
## fling. Every scene on a floor of its own 30 m over the spawn block's junction (nothing an
## earlier check left on the street is under it), loaded at run time like the ragdoll checks.

var _t: Node
var _tree: SceneTree
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check(RagdollFeel.stagger_max_speed > 15.0 and RagdollFeel.stagger_time.x > 0.2 and RagdollFeel.stagger_time.y < 1.0,
		"a rifle round (14.9 m/s) is a stagger of a fraction of a second")
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	if chunk == null and t.has_method("stage_home"):
		await t.stage_home()
		chunk = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the ragdoll feel checks")
	if chunk == null:
		return
	var was := [RagdollJoints.enabled, RagdollJoints.joint_range, RagdollJoints.max_active, RagdollFeel.enabled, RagdollJoints.leave_range]
	RagdollJoints.enabled = true
	RagdollJoints.joint_range = 100000.0
	# The floors stand up to 200 m off; a doll the camera "left" would freeze at once.
	RagdollJoints.leave_range = 100000.0
	RagdollJoints.max_active = 6
	RagdollFeel.enabled = true
	await _check_stagger(city, chunk)
	await _check_trailing(city, chunk)
	await _check_car(city, chunk)
	await _check_stairs(city, chunk)
	await _check_switch(city, chunk)
	RagdollJoints.enabled = was[0]
	RagdollJoints.joint_range = was[1]
	RagdollJoints.max_active = was[2]
	RagdollFeel.enabled = was[3]
	RagdollJoints.leave_range = was[4]
	for n in _made:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await _ticks(2)


## A floor box `size` big whose top centre is `slot` floors along, 30 m over the junction
## north-west of the spawn block. Returns the top's centre (world).
func _floor(city: Node3D, chunk: Node3D, slot: int, size := Vector3(14.0, 1.0, 14.0)) -> Vector3:
	var rect: Rect2 = city.plan.block(0, 0).rect
	var at := Vector2(rect.position.x - 6.0 + float(slot) * 50.0, rect.position.y - 40.0)
	var top: float = chunk.ground_y(at.x, at.y) + 30.0
	_box(chunk, Vector3(at.x, top - size.y * 0.5, at.y), size, 1)
	return chunk.to_global(Vector3(at.x, top, at.y))


func _box(chunk: Node3D, local: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	chunk.add_child(body)
	_made.append(body)
	body.position = local
	return body


## A standing walker on `at` (world), not walking, its model facing `yaw`.
func _walker(city: Node3D, chunk: Node3D, at: Vector3, seed: int, yaw: float = 0.0) -> Pedestrian:
	var p := Pedestrian.new()
	var local := chunk.to_local(at)
	p.setup(Rect2(local.x - 20.0, local.z - 20.0, 40.0, 40.0), 4.0, seed)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_chance = 0.0
	p.life_spawn_chance = 0.0
	p.set_meta("no_trim", true)
	chunk.add_child(p)
	_made.append(p)
	p.global_position = at + Vector3.UP * 0.02
	await _ticks(2)
	p.set_physics_process(false)
	p.global_position = at + Vector3.UP * 0.02
	if p.get("_visual") is Node3D:
		(p.get("_visual") as Node3D).rotation.y = yaw
	return p


func _doll_of(p: Pedestrian) -> Ragdoll:
	var d: Ragdoll = p._doll
	if d != null:
		_made.append(d)
	return d


## Shot by a rifle round (the rifle's own knock): up for a beat, down along the round after.
func _check_stagger(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 0)
	await _ticks(2)
	var p: Pedestrian = await _walker(city, chunk, ground, 8101, PI * 0.5)
	var n0 := RagdollFeel.staggered
	var dir := Vector3.RIGHT
	p.shot(ground + Vector3(0.0, 1.3, 0.0), dir, dir * 14.0 + Vector3.UP * 5.0)
	var doll := _doll_of(p)
	_check(doll != null and doll._joints != null and doll._joints.feel != null and doll._joints.feel.kind == "shot",
		"a rifle round makes the doll a stagger (RagdollFeel)")
	_check(RagdollFeel.staggered == n0 + 1, "the stagger is counted once")
	if doll == null or doll._joints == null:
		return
	var j: RagdollJoints = doll._joints
	var stand := (j.parts["pelvis"] as Node3D).global_position.y - ground.y
	await _ticks(15)
	var mid := (j.parts["pelvis"] as Node3D).global_position.y - ground.y if not j.frozen else 0.0
	var moved := (j.parts["pelvis"] as Node3D).global_position - ground
	_check(mid > stand * 0.8, "a quarter second after the round the person is still on their feet (hips %.2f of %.2f m)" % [mid, stand])
	_check(moved.x > 0.05 and moved.x < 1.2, "they stagger back along the round, not fly off (%.2f m)" % moved.x)
	var down_at := -1
	var worst := 0.0
	for i in 150:
		await _ticks(1)
		if not is_instance_valid(doll):
			break
		if not j.frozen:
			worst = maxf(worst, j.gap())
		var hips := doll._pelvis().y - ground.y
		if down_at < 0 and hips < 0.45:
			down_at = i + 15
	_check(down_at > 20 and down_at < 150, "then they go down (hips under 0.45 m after %.2f s)" % (down_at / 60.0))
	_check(worst < 0.1, "the joints hold through the stagger (worst gap %.3f m)" % worst)
	if is_instance_valid(doll):
		_check((doll._pelvis() - ground).x > 0.3, "and fall along the round (%.2f m on)" % (doll._pelvis() - ground).x)
		doll.queue_free()


## Flung hard into the air: the trunk leads, the limbs trail behind it.
func _check_trailing(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 1)
	await _ticks(2)
	var p: Pedestrian = await _walker(city, chunk, ground, 8102)
	p.knock(Vector3(10.0, 12.0, 0.0))
	var doll := _doll_of(p)
	if doll == null or doll._joints == null:
		_check(false, "a flung doll is jointed")
		return
	var j: RagdollJoints = doll._joints
	_check(j.feel != null and j.feel.kind == "fly", "a plain knock is a flung doll (RagdollFeel fly)")
	await _ticks(18)
	var core := 0.0
	var limbs := 0.0
	var nl := 0
	for name: String in j.parts:
		var v := ((j.parts[name] as RigidBody3D).linear_velocity * Vector3(1, 0, 1)).length()
		if name == "chest" or name == "pelvis":
			core += v * 0.5
		elif name.begins_with("forearm") or name.begins_with("shin"):
			limbs += v
			nl += 1
	limbs /= maxf(nl, 1)
	_check(core > limbs + 0.3, "in the air the trunk leads and the limbs trail (trunk %.1f, hands and feet %.1f m/s)" % [core, limbs])
	doll.queue_free()


## A real car driven into a walker on a long floor: the bumper makes it a car hit, the doll rides
## up onto the bonnet (the hips higher than they stood), and the car's brake leaves it in front.
func _check_car(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 2, Vector3(60.0, 1.0, 14.0))
	await _ticks(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var car := Vehicle.random_car(rng)
	chunk.add_child(car)
	_made.append(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), ground + Vector3(9.0, 0.8, 0.0))
	await _ticks(20)
	var p: Pedestrian = await _walker(city, chunk, ground, 8103, -PI * 0.5)
	var n0 := RagdollFeel.car_wraps
	var stand := 0.85
	var top := -INF
	var doll: Ragdoll = null
	for i in 150:
		if is_instance_valid(car):
			var vx := -14.0 if i < 42 else minf(car.linear_velocity.x + 7.4 / 60.0, 0.0)
			car.linear_velocity = Vector3(vx, car.linear_velocity.y, car.linear_velocity.z)
		await _ticks(1)
		if doll == null and is_instance_valid(p) and p._doll != null:
			doll = _doll_of(p)
		if doll != null and is_instance_valid(doll):
			top = maxf(top, doll._pelvis().y - ground.y)
	_check(RagdollFeel.car_wraps == n0 + 1 and doll != null, "a car's bumper knocks the walker down as a car hit")
	if doll == null or not is_instance_valid(doll):
		return
	_check(top > stand + 0.05 and top < 3.5, "the body rides up over the bonnet, not off over the roofs (hips up to %.2f m)" % top)
	var ahead := (car.global_position - doll._pelvis()).x if is_instance_valid(car) else 0.0
	_check(ahead > 0.5, "and slides off ahead of the braking car (%.1f m in front of it)" % ahead)
	doll.queue_free()


## Knocked at the top of a flight of ten steps: it rolls down them, not stop on the third.
func _check_stairs(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 3, Vector3(14.0, 1.0, 20.0))
	var base := chunk.to_local(ground)
	for i in 10:
		var h := 1.7 - 0.17 * float(i)
		var z := -0.15 + 0.3 * float(i) + (0.0 if i > 0 else -1.0)
		_box(chunk, base + Vector3(0.0, h * 0.5, z), Vector3(4.0, h, 0.3 if i > 0 else 2.3), 1)
	await _ticks(2)
	var p: Pedestrian = await _walker(city, chunk, ground + Vector3(0.0, 1.7, -1.2), 8104)
	if OS.get_environment("RF_DEBUG") == "1":
		print("RF walker at ", p.global_position - ground)
	p.knock(Vector3(0.0, 1.5, 2.2))
	var doll := _doll_of(p)
	if doll == null or doll._joints == null:
		_check(false, "a doll on the steps is jointed")
		return
	var j: RagdollJoints = doll._joints
	var rolled := false
	for i in int((RagdollJoints.settle_max + 1.0) * 60.0):
		await _ticks(1)
		if not is_instance_valid(doll):
			break
		if j.feel != null and j.feel.rolling > 0.0:
			rolled = true
		if OS.get_environment("RF_DEBUG") == "1" and i % 20 == 0:
			print("RF stairs %d hips %s frozen %s" % [i, doll._pelvis() - ground, j.frozen])
		if j.frozen:
			break
	_check(rolled, "the doll knows it is rolling down the steps")
	if not is_instance_valid(doll):
		return
	var at := doll._pelvis() - ground
	_check(at.y < 0.8 and at.z > 1.4, "it ends at the foot of the flight, not on the top steps (hips %.2f m up, %.1f m along)" % [at.y, at.z])
	var mats_ok := doll.bodies.all(func(b): return (b as RigidBody3D).physics_material_override == null or (b as RigidBody3D).physics_material_override.friction > 0.5)
	_check(mats_ok, "the rolling material is gone once it lies still")
	doll.queue_free()


## RAGDOLL_FEEL=0: the joints' own fling, no feel on the doll.
func _check_switch(city: Node3D, chunk: Node3D) -> void:
	var ground := _floor(city, chunk, 4)
	await _ticks(2)
	RagdollFeel.enabled = false
	var p: Pedestrian = await _walker(city, chunk, ground, 8105)
	p.shot(ground + Vector3(0.0, 1.3, 0.0), Vector3.RIGHT, Vector3.RIGHT * 14.0 + Vector3.UP * 5.0)
	var doll := _doll_of(p)
	_check(doll != null and doll._joints != null and doll._joints.feel == null, "RAGDOLL_FEEL=0 leaves the joints' own fling")
	RagdollFeel.enabled = true
	if doll != null:
		doll.queue_free()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
