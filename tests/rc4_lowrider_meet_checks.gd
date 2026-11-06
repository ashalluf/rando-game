extends RefCounted
## The lowrider meet at eye level (LowriderMeetLook, the lowrider_meet reference camera in
## tools/refcams/cameras_w7.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: a parked row car holds a display stance by hash (laid, locked up, on three, nose up; a
## show car stays laid between routines) and its owner is out (nobody in the glass, lamps off), a
## show car keeps its driver; a three-wheel takes its wheel well off the road (three_lift); the
## crowd gathers round the show cars on the pavement; the chairs have sitters by the chairs; the
## camera row and its staging key; RC4_LOWRIDER_MEET=0 puts the old numbers back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := LowriderMeetLook.enabled
	LowriderMeetLook.enabled = true
	_stances()
	await _car(t, city)
	_crowd()
	_camera()
	LowriderMeetLook.enabled = false
	var spot := [Vector2.ZERO, 0.0, Lowrider.HARDTOP, 12345, false]
	var off := LowriderMeetLook.stance_for(spot)
	_t._check(int(off[0]) == LowriderMeetLook.Stance.LAID and LowriderMeetLook.sitter_spots({}, [[Vector2.ZERO, 0.0, 7, 1.0]]).is_empty(),
		"RC4_LOWRIDER_MEET=0: every parked car laid out and no sitters (the old meet)")
	LowriderMeetLook.enabled = was


func _stances() -> void:
	var counts := [0, 0, 0, 0]
	var show_laid := true
	for i in 400:
		var look := absi(hash([i, "rc4lr"]))
		counts[int(LowriderMeetLook.stance_for([Vector2.ZERO, 0.0, Lowrider.HARDTOP, look, false])[0])] += 1
		show_laid = show_laid and int(LowriderMeetLook.stance_for([Vector2.ZERO, 0.0, Lowrider.HARDTOP, look, true])[0]) == LowriderMeetLook.Stance.LAID
		var again := LowriderMeetLook.stance_for([Vector2.ZERO, 0.0, Lowrider.HARDTOP, look, false])
		show_laid = show_laid and again == LowriderMeetLook.stance_for([Vector2.ZERO, 0.0, Lowrider.HARDTOP, look, false])
	_t._check(counts[0] > 150 and counts[1] > 40 and counts[2] > 30 and counts[3] > 25 and show_laid,
		"parked meet cars hold display stances by hash (laid %d, locked %d, three %d, nose %d of 400), show cars laid" % counts)


func _car(t: Node, city: Node3D) -> void:
	var tree := t.get_tree()
	var player := tree.get_first_node_in_group("player") as Node3D
	var car := Lowrider.make(Lowrider.HARDTOP, 4242)
	car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0, "v": 0.0, "half": 2.7, "rear": 2.7, "parked": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = player.global_position + Vector3(0.0, 420.0, 30.0)
	city.add_child(car)
	for i in 3:
		await tree.process_frame
	var h: Node = car.get_node_or_null("Hydraulics")
	if h == null or car._wheel_rigs.size() != 4:
		_t._check(false, "a lowrider with hydraulics and four wheel rigs to check")
		car.queue_free()
		return
	h.set("mode", Lowrider.Hydraulics.Mode.PARKED)
	_t._check(car.lights_running(), "a row car starts with a driver and lit lamps (a traffic-style car)")
	LowriderMeetLook.dress_car(car, [Vector2.ZERO, 0.0, Lowrider.HARDTOP, 4242, false])
	_t._check(not car.lights_running() and car._cabin_seats() == 0,
		"a parked meet car is empty: its owner is out on the kerb, its lamps off")
	var stroke := float(h.get("stroke"))
	h.call("set_stance", LowriderMeetLook.Stance.LOCKED, 1.0)
	var hs: PackedFloat32Array = (h.call("heights") as PackedFloat32Array).duplicate()
	var locked := hs[0] > stroke * 0.8 and hs[3] > stroke * 0.8
	h.call("advance", 3.0)
	var held: PackedFloat32Array = h.call("heights")
	_t._check(locked and absf(held[0] - hs[0]) < 0.01 and String(h.call("routine")) == "",
		"a locked-up stance stands all four corners up (%.2f / %.2f) and holds while parked" % [hs[0], hs[3]])
	h.call("set_stance", LowriderMeetLook.Stance.THREE, 1.0)
	h.call("advance", 1.0)
	var up := (car._wheel_rigs[1][0] as Node3D).position.y - float(car._wheel_rigs[1][5])
	var other := (car._wheel_rigs[0][0] as Node3D).position.y - float(car._wheel_rigs[0][5])
	_t._check(up > float(h.get("three_lift")) * 0.85 and other < 0.01, "parked on three: one front wheel %.2f m off the road, the other down" % up)
	h.call("set_stance", LowriderMeetLook.Stance.LAID, 1.0)
	h.call("perform", "three", -1.0)
	h.call("advance", 2.0)
	var lifted := (car._wheel_rigs[0][0] as Node3D).position.y - float(car._wheel_rigs[0][5])
	_t._check(lifted > float(h.get("three_lift")) * 0.85,
		"a show three-wheel takes its front wheel %.2f m off the road (was 0.2)" % lifted)
	var show := Lowrider.make(Lowrider.COUPE, 777)
	show.traffic = car.traffic.duplicate()
	show.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	show.freeze = true
	show.position = car.position + Vector3(8.0, 0.0, 0.0)
	city.add_child(show)
	await tree.process_frame
	LowriderMeetLook.dress_car(show, [Vector2.ZERO, 0.0, Lowrider.COUPE, 777, true])
	_t._check(show.lights_running(), "a show car keeps its driver at the switches")
	car.queue_free()
	show.queue_free()
	await tree.process_frame


func _crowd() -> void:
	var m := {"axis": CityPlan.AXIS_Z, "side": 1.0, "centre": 600.0, "width": 18.0, "lo": 800.0, "hi": 890.0,
		"lane": 606.5, "seed": 99, "cars": 10, "index": 4, "owner": Vector2i.ZERO}
	var spots := LowriderMeet.layout(m)
	for i in spots.size():
		spots[i][4] = i == 2 or i == 6
	var want := 20
	var people := LowriderMeetLook.people_spots(m, spots, want)
	var kerb := 609.0
	var near_show := 0
	var on_pave := true
	for p: Array in people:
		var at: Vector2 = p[0]
		on_pave = on_pave and at.y > kerb + 0.3
		for j in [2, 6]:
			if at.distance_to(spots[j][0]) < 6.0:
				near_show += 1
				break
	_t._check(people.size() == want and on_pave and near_show >= 9,
		"the crowd stands on the pavement and gathers round the show cars (%d of %d within 6 m)" % [near_show, want])
	var chairs := LowriderMeet.chair_spots(m, spots)
	var sitters := LowriderMeetLook.sitter_spots(m, chairs)
	var by_chairs := true
	for s: Array in sitters:
		var best := INF
		for c: Array in chairs:
			best = minf(best, (s[0] as Vector2).distance_to(c[0]))
		by_chairs = by_chairs and best < 0.7
	_t._check(chairs.is_empty() or (sitters.size() >= chairs.size() and by_chairs),
		"%d people in the folding chairs (%d pairs), each at a chair" % [sitters.size(), chairs.size()])


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var row := {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if String(c.name) == "lowrider_meet":
				row = c
	_t._check(not row.is_empty() and row.get("lowrider_meet", null) is Dictionary and float(row.hour) == 19.5
		and String(row.lowrider_meet.get("pose", "")).contains("three"),
		"the lowrider_meet camera row: 19:30, the meet held on and a car posed on three")
