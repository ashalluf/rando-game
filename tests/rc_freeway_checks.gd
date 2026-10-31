extends RefCounted
## The freeway refcam pass (FreewayFill, FreewayLook) for tests/smoke_test.gd. Loaded at run time.
## Checks: the fill's cap, retirement and route shares; its slots per lane (jittered so lanes do not
## line up), offered nearest the player first, the dense window while filling and only the outer
## band once filled, never a taken slot; the A/B gives the old numbers; a car spawned into a lane's
## slot keeps that lane and is never a truck in a fast lane; the deck and paint materials carry the
## look's values, and its A/B leaves the shaders' old defaults. Leans on nothing an earlier check left.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_fill_pure()
	_look()
	await _spawn(city)


func _fill_pure() -> void:
	_t._check(FreewayFill.enabled, "freeway fill: on by default (FREEWAY_FILL=0 is the A/B)")
	_t._check(FreewayFill.cap(70) > 70 and FreewayFill.retire_reach(620.0) < 620.0 * 1.35,
		"freeway fill: a bigger cap (%d) kept nearer (%.0f m)" % [FreewayFill.cap(70), FreewayFill.retire_reach(620.0)])
	var sh: Array[int] = FreewayFill.shares([30.0, 500.0], 100, 620.0)
	_t._check(sh.size() == 2 and sh[0] > sh[1] * 2 and sh[0] + sh[1] <= 100,
		"freeway fill: the route under the player takes most of the cars (%s)" % str(sh))
	# Lanes' slots do not line up.
	var same := 0
	for slot in 40:
		var t0 := FreewayFill.slot_t(0, 1, 0, slot)
		var t1 := FreewayFill.slot_t(0, 1, 1, slot)
		if absf(t0 - t1) < 3.0:
			same += 1
		if FreewayFill.slot_of(t0) != slot:
			same += 100
	_t._check(same < 8, "freeway fill: each lane's slots are its own, jittered inside the slot (%d alike)" % same)
	# Nearest first, the window, the band, taken slots.
	var anchor := 2000.0
	var taken := {Vector3i(FreewayFill.slot_of(anchor), 1, 2): true}
	var fill: Array = FreewayFill.candidates(0, anchor, 5000.0, taken, true, Freeway.LANES)
	var ok := not fill.is_empty()
	var last := -1.0
	for c: Array in fill:
		var d := absf(float(c[0]) - anchor)
		ok = ok and d >= last - 1e-3 and d <= FreewayFill.DENSE_REACH and d >= FreewayFill.KEEP_CLEAR
		last = d
		ok = ok and not taken.has(Vector3i(FreewayFill.slot_of(float(c[0])), int(c[1]), int(c[2])))
	_t._check(ok, "freeway fill: filling offers the free slots of the window, nearest first, none on the player (%d)" % fill.size())
	var steady: Array = FreewayFill.candidates(0, anchor, 5000.0, {}, false, Freeway.LANES)
	var band := not steady.is_empty()
	for c: Array in steady:
		band = band and absf(float(c[0]) - anchor) >= FreewayFill.INFLOW_FROM
	_t._check(band, "freeway fill: once filled, cars enter only past %.0f m (%d slots)" % [FreewayFill.INFLOW_FROM, steady.size()])
	FreewayFill.enabled = false
	var old_ok := FreewayFill.cap(70) == 70 and is_equal_approx(FreewayFill.retire_reach(620.0), 620.0 * 1.35) \
		and FreewayFill.shares([30.0, 500.0], 100, 620.0)[0] == 50 and FreewayFill.shares([30.0, 500.0], 100, 620.0)[1] == 50
	FreewayFill.enabled = true
	_t._check(old_ok, "freeway fill: the A/B is the old cap, reach and even shares")


func _look() -> void:
	var deck := FreewayCloseup.deck_material()
	var paint := FreewayKit.paint_material()
	_t._check(FreewayLook.enabled and deck.get_shader_parameter("tine_fade") == FreewayLook.TINE_FADE
		and bool(deck.get_shader_parameter("rumble_scoop")) and bool(paint.get_shader_parameter("joint_steel")),
		"freeway look: the deck's tining fade, rumble scoops and steel joints are set")
	var src := FileAccess.get_file_as_string("res://shaders/freeway_deck.gdshader")
	_t._check(src.contains("uniform vec2 tine_fade = vec2(0.35, 1.0);") and src.contains("uniform bool rumble_scoop = false;")
		and FileAccess.get_file_as_string("res://shaders/freeway_paint.gdshader").contains("uniform bool joint_steel = false;"),
		"freeway look: the shaders' defaults are the old look (FREEWAY_LOOK=0)")


func _spawn(city: Node3D) -> void:
	var tm: Node = city.get_node_or_null("Traffic")
	var plan: CityPlan = city.plan
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	if tm == null or fw == null or fw.routes.is_empty():
		_t._check(false, "freeway fill: the city has traffic and a freeway")
		return
	var ri := 0
	var t := fw.length_of(ri) * 0.5
	var lanes_ok := true
	var trucks_fast := 0
	var made: Array = []
	for k in 8:
		var li := k % Freeway.LANES
		var before: int = (tm.freeway_cars as Array).size()
		tm._spawn_freeway_car(ri, t + float(k) * 60.0, 1, li)
		var cars: Array = tm.freeway_cars
		if cars.size() <= before:
			lanes_ok = false
			continue
		var car: Vehicle = cars[cars.size() - 1]
		made.append(car)
		var got := TrafficAI.fw_lane(fw, car.traffic)
		# FreewayIncidents may move a car off a blocked lane; otherwise it keeps its slot's lane.
		if got != li and FreewayIncidents.spawn_lane(ri, float(car.traffic.t), 1, li) == li:
			lanes_ok = false
		if BigVehicles.is_big(car.body_type) and li < Freeway.LANES - 2:
			trucks_fast += 1
	_t._check(lanes_ok and trucks_fast == 0, "freeway fill: a car spawned into a lane's slot keeps that lane, no truck in a fast lane")
	for car: Vehicle in made:
		if is_instance_valid(car):
			(tm.freeway_cars as Array).erase(car)
			tm._retire(car)
	await _t.get_tree().process_frame
