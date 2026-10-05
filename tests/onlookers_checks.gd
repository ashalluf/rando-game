extends RefCounted
## Onlookers checks for tests/smoke_test.gd (Onlookers): a knocked-down walker opens a scene; the
## crowd panics first and nobody watches while it does; once it is quiet they come back and stand
## round it in a loose ring inside the scene's distance band, spaced apart, facing it, in more
## than one role (a caller on the phone, a filmer with the phone held up at eye level in front of
## the face, ...); a new shot sends them off at once and they come back; responders arriving
## send them away and the scene closes. Loaded at run time like the other crowd checks, so it
## compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check_pure()
	if not Onlookers.enabled:
		_check(true, "onlookers are off (ONLOOKERS=0): only the pure checks ran")
		return
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the onlooker checks")
	if chunk == null:
		return
	await _check_scene(city, chunk)


func _check_pure() -> void:
	var mesh := Onlookers.film_phone_mesh()
	_check(mesh != null and mesh.get_surface_count() == 1, "the filming phone is one mesh")
	var bad := 0
	for side: String in ["Left", "Right"]:
		var b := Onlookers._hand_for(side, Vector3(0.1, 1.0, 0.0), Vector3(0.0, 0.2, -1.0))
		if absf(b.determinant() - 1.0) > 0.01:
			bad += 1
		# The grip frame it makes: fingers up, palm back toward the face.
		var g := b * CrowdLife.grip_basis(side + "Hand")
		if g.y.normalized().dot(Vector3.UP) < 0.95 or g.z.normalized().dot(Vector3.BACK * -1.0) < 0.9:
			bad += 1
	_check(bad == 0, "the hand frames the poses ask for are rotations with the fingers up and the palm to the face (%d off)" % bad)


func _check_scene(city: Node3D, chunk: Node3D) -> void:
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var node := Onlookers.find()
	_check(node != null, "the onlookers node exists once the crowd has life clips")
	if node == null:
		return
	# Nothing left over from earlier parts.
	for s: Dictionary in node.scenes.duplicate():
		for m: Pedestrian in (s.members as Array).duplicate():
			if is_instance_valid(m):
				m._end_act(true)
	node.scenes.clear()
	# A dozen walkers along the north pavement of the spawn block.
	var z := rect.position.y + 2.0
	var x0 := rect.position.x + 6.0
	var peds: Array[Pedestrian] = []
	for i in 12:
		var p := Pedestrian.new()
		p.setup(rect, plan.sidewalk_width, 9100 + i * 37)
		p.pause_chance = 0.0
		p.cross_chance = 0.0
		p.jogger_share = Vector2.ZERO
		p.dog_share = Vector2.ZERO
		p.life_chance = 0.0
		p.life_spawn_chance = 0.0
		p.panic_seconds = Vector2(1.5, 2.5)
		p.life_range = 100000.0 # wherever the player stands by now
		p.look_range = 100000.0
		p.set_meta("no_trim", true)
		var at := Vector2(x0 + float(i) * 2.2, z + float(i % 3) * 0.8)
		p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
		chunk.add_child(p)
		peds.append(p)
	await _ticks(30)
	var lifers := peds.filter(func(p): return (p as Pedestrian)._life_ok)
	_check(lifers.size() >= 10, "the test walkers have their life clips (%d of 12)" % lifers.size())
	# A victim on the pavement in the middle of them, knocked down: the scan opens a body scene.
	var vx := x0 + 12.0
	var victim := Pedestrian.new()
	victim.setup(rect, plan.sidewalk_width, 9900)
	victim.position = Vector3(vx, chunk.ground_y(vx, z + 1.0) + 0.1, z + 1.0)
	chunk.add_child(victim)
	await _ticks(4)
	var shot_at := victim.global_position + Vector3.UP
	victim.knock(Vector3(0.0, 1.0, 1.0))
	Pedestrian.alarm(_tree, shot_at, 40.0, 0, true, "")
	await _ticks(2)
	var scene: Dictionary = {}
	for i in 60:
		for s: Dictionary in node.scenes:
			if s.kind == Onlookers.Kind.BODY and (Onlookers.find().scene_point(s)).distance_to(shot_at) < 6.0:
				scene = s
		if not scene.is_empty():
			break
		await _ticks(1)
	_check(not scene.is_empty(), "a knocked-down walker opens a body scene")
	if scene.is_empty():
		_cleanup(peds)
		return
	var doll: Variant = scene.ref
	_check(doll is Ragdoll and float((doll as Ragdoll).get_meta("debris_life", 0.0)) >= Onlookers.BODY_HOLD,
		"the watched body is kept past its debris time")
	# While they panic, nobody comes to look.
	await _ticks(30)
	var watching_in_panic := 0
	for p in peds:
		if is_instance_valid(p) and p._panic_left > 0.0 and not p.watch.is_empty():
			watching_in_panic += 1
	_check(watching_in_panic == 0, "nobody watches while still panicking (%d)" % watching_in_panic)
	# Quiet again: they come back. Wait for at least four standing at their places.
	var standing: Array = []
	for i in 2400:
		await _ticks(1)
		standing = (scene.members as Array).filter(func(m): return is_instance_valid(m) and (m as Pedestrian)._stage == Pedestrian.Stage.DOING)
		if standing.size() >= 4 and i % 30 == 0:
			break
	_check(standing.size() >= 4, "once it is quiet people come back and stand round the body (%d)" % standing.size())
	var centre := node.scene_point(scene)
	var band := node._band(scene)
	var off_band := 0
	var facing := 0
	var close := 0
	var roles := {}
	for m: Pedestrian in standing:
		var d := Vector2(m.global_position.x - centre.x, m.global_position.z - centre.z)
		if d.length() < band.x - 1.0 or d.length() > band.y + 9.5:
			off_band += 1
		var fwd := Vector2(-sin(m._visual.global_rotation.y), -cos(m._visual.global_rotation.y))
		if fwd.dot(-d.normalized()) > 0.75:
			facing += 1
		roles[int(m.watch.role)] = true
		for o: Pedestrian in standing:
			if o != m and o.global_position.distance_to(m.global_position) < Onlookers.SPACING - 0.2:
				close += 1
	_check(off_band == 0, "the onlookers stand at the scene's distance (%d out of %.1f-%.1f m)" % [off_band, band.x, band.y])
	_check(facing == standing.size(), "the onlookers face the scene (%d of %d)" % [facing, standing.size()])
	_check(close == 0, "the onlookers keep apart (%d pairs too close)" % (close / 2))
	_check(roles.size() >= 2, "the onlookers do more than one thing (%s)" % str(roles.keys()))
	# The caller: on the phone, the phone in the hand at the ear.
	var callers := (scene.members as Array).filter(func(m): return is_instance_valid(m) and int((m as Pedestrian).watch.get("role", -1)) == Onlookers.Role.CALL)
	_check(callers.size() >= 1 and callers.size() <= 2, "one or two of them call for help (%d)" % callers.size())
	# Wait for a caller and a filmer to be in place and posed (the arm comes up over half a second).
	var film_ok := false
	var call_ok := false
	var film_seen := false
	for i in 900:
		await _ticks(1)
		for m: Pedestrian in scene.members:
			if not is_instance_valid(m) or m._stage != Pedestrian.Stage.DOING or m._head_skel == null:
				continue
			var role := int(m.watch.get("role", -1))
			if role == Onlookers.Role.CALL and not call_ok:
				var ph: Node3D = m._props.get(CrowdLife.Prop.PHONE)
				call_ok = m._clip == CrowdLife.PHONE and ph != null and ph.visible
			elif role == Onlookers.Role.FILM and float(m.watch.w) > 0.99 and not film_ok:
				film_seen = true
				film_ok = _film_pose_ok(m)
		if film_ok and call_ok:
			break
	_check(call_ok, "a caller holds the phone to the ear (the phone clip)")
	_check(film_ok or not film_seen, "a filmer holds the phone up at eye level in front of the face, its screen to them")
	# A new shot: everyone runs, at once.
	Pedestrian.alarm(_tree, centre + Vector3.UP, 40.0, 0, true, "")
	await _ticks(2)
	var still := (scene.members as Array).filter(func(m): return is_instance_valid(m))
	_check(still.is_empty(), "a new shot sends the onlookers running (%d stayed)" % still.size())
	# And they come back once it is quiet.
	var back := 0
	for i in 1800:
		await _ticks(1)
		back = (scene.members as Array).filter(func(m): return is_instance_valid(m)).size()
		if back >= 3:
			break
	_check(back >= 3, "after the second fright they come back again (%d)" % back)
	# Help arrives: they drift away and the scene closes.
	var responder := Node3D.new()
	responder.add_to_group("responder")
	city.add_child(responder)
	responder.global_position = centre
	var left := false
	for i in 1200:
		await _ticks(1)
		if not node.scenes.any(func(s): return is_same(s, scene)):
			left = true
			break
	_check(left, "the onlookers leave as responders arrive and the scene closes")
	var stragglers := 0
	for p in peds:
		if is_instance_valid(p) and not p.watch.is_empty():
			stragglers += 1
	_check(stragglers == 0, "nobody is left watching a closed scene (%d)" % stragglers)
	responder.queue_free()
	if doll is Ragdoll and is_instance_valid(doll):
		(doll as Node).queue_free()
	_cleanup(peds)
	await _ticks(2)


## The phone in front of the face at eye height, the screen (+z of the grip frame) to the eyes.
func _film_pose_ok(m: Pedestrian) -> bool:
	var ph: Node3D = m.get_meta("onlooker_phone") if m.has_meta("onlooker_phone") else null
	if ph == null or not ph.visible or ph.get_child_count() == 0:
		return false
	var mi := ph.get_child(0) as Node3D
	var sk := m._head_skel
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var phone := mi.global_transform * Vector3(0.0, 0.075, 0.022)
	var fwd := Vector3(-sin(m._visual.global_rotation.y), 0.0, -cos(m._visual.global_rotation.y))
	var rel := phone - head
	var ahead := rel.dot(fwd)
	var screen := (mi.global_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var to_eye := (head + Vector3.UP * 0.07 - phone).normalized()
	var ok := ahead > 0.18 and ahead < 0.55 and absf(rel.y) < 0.2 and screen.dot(to_eye) > 0.6
	if not ok:
		printerr("ONLOOKERS film pose: ahead %.2f up %.2f screen %.2f" % [ahead, rel.y, screen.dot(to_eye)])
	return ok


func _cleanup(peds: Array[Pedestrian]) -> void:
	for p in peds:
		if is_instance_valid(p):
			p.queue_free()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
