extends RefCounted
## Crowd life checks for tests/smoke_test.gd (GAME_PLAN G5, CrowdLife): every crowd rig has its
## "life" clips, retargeted sensibly (the phone at the ear, the hips down on a seat, the jog's
## feet on the ground); the people on the spawn block stop to talk in a group facing each other,
## sit on a bench with the hips on the seat and the feet on the pavement, lean on nothing that
## is not a wall; what they carry is in their hands near the player and gone far off; nobody far
## away does anything but walk; and a gunshot ends all of it. Loaded at run time like the other
## crowd checks, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check_library()
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the crowd life checks")
	if chunk == null:
		return
	await _check_behaviour(city, chunk)


func _check_library() -> void:
	var names := ["idle", "talk", "sit_down", "sit", "sit_talk", "stand_up", "jog", "phone", "fold", "drink", "nod", "shake", "rail"]
	var missing := 0
	var bad_tracks := 0
	for path: String in Pedestrian.MODELS:
		var lib := CrowdLife.library(path)
		if lib == null:
			missing += 1
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		for n: String in names:
			if not lib.has_animation(n):
				missing += 1
				continue
			var a := lib.get_animation(n)
			for tr in a.get_track_count():
				var bone := String(a.track_get_path(tr).get_concatenated_subnames())
				if skel.find_bone(bone) < 0:
					bad_tracks += 1
		inst.free()
	_check(missing == 0, "every crowd rig has all %d life clips (%d missing)" % [names.size(), missing])
	_check(bad_tracks == 0, "the life clips only animate the crowd rig's own bones (%d strays)" % bad_tracks)
	# The retarget, measured on one rig: the call puts the right hand by the head, the seat
	# lowers the hips by a third, and the jog keeps a foot on the ground.
	var path: String = Pedestrian.MODELS[0]
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	_t.get_tree().root.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var anim: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	CrowdLife.attach(anim, path)
	anim.play(CrowdLife.PHONE)
	anim.seek(anim.get_animation(CrowdLife.PHONE).length * 0.5, true)
	skel.force_update_all_bone_transforms()
	var hand := skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
	var head := skel.get_bone_global_pose(skel.find_bone("Head")).origin
	_check(hand.distance_to(head) < 26.0, "on the phone the hand is by the head (%.0f cm)" % hand.distance_to(head))
	var rest_hips := skel.get_bone_global_rest(skel.find_bone("Hips")).origin.y
	anim.play(CrowdLife.SIT)
	anim.seek(0.5, true)
	skel.force_update_all_bone_transforms()
	var sit_hips := skel.get_bone_global_pose(skel.find_bone("Hips")).origin.y
	_check(sit_hips < rest_hips * 0.75 and sit_hips > rest_hips * 0.5,
		"sitting lowers the hips to a chair's height (%.0f of %.0f cm)" % [sit_hips, rest_hips])
	var low := INF
	anim.play(CrowdLife.JOG)
	var jl := anim.get_animation(CrowdLife.JOG).length
	for i in 12:
		anim.seek(jl * i / 12.0, true)
		skel.force_update_all_bone_transforms()
		for b in ["LeftToeBase", "RightToeBase"]:
			low = minf(low, skel.get_bone_global_pose(skel.find_bone(b)).origin.y)
	var rest_toe := skel.get_bone_global_rest(skel.find_bone("LeftToeBase")).origin.y
	_check(absf(low - rest_toe) < 2.0, "the jog's feet reach the ground (lowest toe %.1f cm, rest %.1f)" % [low, rest_toe])
	inst.free()


func _check_behaviour(city: Node3D, chunk: Node3D) -> void:
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var player: Node3D = _tree.get_first_node_in_group("player")
	var z := rect.position.y + 2.0
	var x0 := rect.position.x + 8.0
	# A bench of our own on the north pavement, facing the road (north, -Z).
	var bench := Vector3(x0 + 10.0, chunk.ground_y(x0 + 10.0, rect.position.y + 3.2), rect.position.y + 3.2)
	CrowdLife.add_seat(chunk, bench, 0.0, {"dead": false})
	var peds: Array[Pedestrian] = []
	for i in 4:
		var p := Pedestrian.new()
		p.setup(rect, plan.sidewalk_width, 7100 + i * 31)
		p.pause_chance = 0.0
		p.cross_chance = 0.0
		p.jogger_share = Vector2.ZERO
		p.dog_share = Vector2.ZERO
		p.life_spawn_chance = 0.0
		p.life_range = 100000.0 # wherever the player stands by now
		p.look_range = 100000.0
		var at := Vector2(x0 + float(i) * 1.5, z)
		p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
		chunk.add_child(p)
		peds.append(p)
	await _ticks(40) # _update_lod has run: they are near the player
	var lead := peds[0]
	_check(lead._life_ok and lead._life_near, "a walker near the player has the life clips and is in life range")
	# Same seed, same person.
	var twin := Pedestrian.new()
	twin.setup(rect, plan.sidewalk_width, 7100)
	twin.jogger_share = Vector2.ZERO
	twin.dog_share = Vector2.ZERO
	twin.position = lead.position
	chunk.add_child(twin)
	await _ticks(1)
	_check(twin._carry == lead._carry and twin._jogger == lead._jogger, "what a person carries is rolled from the seed")
	twin.free()
	# A conversation: the first walker gathers the others round a spot.
	_check(lead._plan_talk(true), "a walker finds people nearby to talk to")
	await _ticks(30)
	var group: Dictionary = lead._group
	var members: Array = group.get("members", [])
	var facing := 0
	for m: Pedestrian in members:
		var to: Vector2 = (group.centre as Vector2) - Vector2(m.position.x, m.position.z)
		var fwd := Vector2(-sin(m._visual.rotation.y), -cos(m._visual.rotation.y))
		if fwd.dot(to.normalized()) > 0.8:
			facing += 1
	_check(members.size() >= 2 and facing == members.size(), "the group stands facing its middle (%d of %d)" % [facing, members.size()])
	var talking := members.any(func(m): return (m as Pedestrian)._clip == CrowdLife.TALK)
	await _ticks(260)
	talking = talking or members.any(func(m): return (m as Pedestrian)._clip == CrowdLife.TALK)
	_check(talking, "somebody in the group is talking")
	# A seat: someone free walks to the bench and sits.
	var sitter: Pedestrian = null
	for p in peds:
		if p._act == CrowdLife.Act.NONE:
			sitter = p
			break
	if sitter == null:
		sitter = peds[3]
		sitter._end_act(true)
	_check(sitter._plan_sit(true), "a walker finds the bench's free seat")
	await _ticks(90)
	var skel := sitter._head_skel
	var hips_y := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin).y
	var foot_y := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftToeBase")).origin).y
	var ground := sitter.global_position.y # the pavement it stands on
	_check(sitter._clip == CrowdLife.SIT or sitter._clip == CrowdLife.SIT_TALK, "the sitter plays the sitting clip (%s)" % sitter._clip)
	_check(absf(hips_y - ground - CrowdLife.SEAT_HEIGHT - CrowdLife.HIP_OVER_SEAT) < 0.06,
		"the sitter's hips are on the bench (%.2f m over the pavement)" % (hips_y - ground))
	_check(foot_y - ground < 0.12, "the sitter's feet stay on the pavement (toe %.2f m up)" % (foot_y - ground))
	var seat := CrowdLife.free_seat(chunk, Vector2(bench.x, bench.z), 2.0)
	_check(not seat.is_empty() and (seat.p as Vector2).distance_to(Vector2(sitter._seat.p)) > 0.5, "the taken seat is not offered again")
	# Props: a carrier near the player holds it; far off it is gone and nobody stops.
	var carrier := peds[1]
	carrier._carry = CrowdLife.Carry.CUP
	await _ticks(4)
	var cup: Node3D = carrier._props.get(CrowdLife.Prop.CUP)
	_check(cup != null and cup.visible, "a coffee drinker near the player holds a cup")
	# A shot: everybody's stop ends at once, seats are freed.
	Pedestrian.alarm(_tree, sitter.global_position + Vector3(3.0, 1.0, 0.0), 30.0, 0, true, "")
	await _ticks(2)
	var busy := 0
	for p in peds:
		if is_instance_valid(p) and p._act != CrowdLife.Act.NONE:
			busy += 1
	_check(busy == 0, "a gunshot ends every stop (%d still at it)" % busy)
	_check(CrowdLife.free_seat(chunk, Vector2(bench.x, bench.z), 2.0).size() > 0 and sitter._seat.is_empty(), "the bench is free again")
	# Far from the player: no stops, no props.
	var far := Pedestrian.new()
	far.setup(rect, plan.sidewalk_width, 7300)
	far.position = carrier.position
	chunk.add_child(far)
	far._carry = CrowdLife.Carry.CUP
	far.life_range = 0.5 # as if the player were far off
	await _ticks(40)
	var far_cup: Node3D = far._props.get(CrowdLife.Prop.CUP)
	_check(not far._life_near and far._act == CrowdLife.Act.NONE and (far_cup == null or not far_cup.visible),
		"a walker out of life range only walks, empty-handed")
	for p in peds:
		if is_instance_valid(p):
			p.queue_free()
	far.queue_free()
	var seats: Array = chunk.get_meta("life_seats", [])
	chunk.set_meta("life_seats", seats.filter(func(s): return (s.p as Vector2).distance_to(Vector2(bench.x, bench.z)) > 1.0))
	await _ticks(2)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
