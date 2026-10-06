extends RefCounted
## Freeway incidents checks for tests/smoke_test.gd (fleet wave 2, "freeway-incidents"): the
## schedule is pure and keeps off the ramps and the route ends; the stall's script (a car on the
## shoulder, the patrol car behind it, the tow ahead, its bed down and up, the car winched on, all
## of them away again); the kit's meshes inside their budgets and the CMS lettering; a CMS saying
## what is ahead; then live on the deck: a forced stall builds its car, patrol car, tow truck and
## driver where the clock says, the tow winches the car onto its bed and leaves with it; a car
## driving at a mattress in its lane changes lanes round it (or stops short, never through it);
## the slow lane moves over past the stall; spawns keep out of a blocked lane; a slowdown slows
## the cars in it; and with the switch off nothing changes. Loaded at run time (names autoload
## users freely).

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _player: Player
var _fw: Freeway


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_player = _tree.get_first_node_in_group("player") as Player
	_fw = _plan.macro.freeway if _plan.macro else null
	if _fw == null or _fw.routes.is_empty():
		_check(false, "freeway incidents: the city has a freeway to check")
		return
	var node := FreewayIncidents.current
	_check(node != null and is_instance_valid(node) and node.get_parent() == _traffic, "freeway incidents: the traffic carries the incidents node (%s)" % [node != null])
	if node == null:
		return
	if _player.is_driving():
		_player.exit_vehicle()
	var home: Vector3 = _ws.to_world(_player.global_position)
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	_schedule()
	_stall_script()
	_kit()
	var max_was := _traffic.max_freeway_cars
	_traffic.max_freeway_cars = 0
	var hold_was := FreewayIncidents.hold
	FreewayIncidents.hold = false
	_clear_freeway()
	await _live_stall(node)
	_clear_freeway()
	await _mattress_swerve(node)
	_clear_freeway()
	await _slowdown(node)
	_clear_freeway()
	FreewayIncidents.clear_forced()
	await _ticks(2)
	FreewayIncidents.hold = hold_was
	_traffic.max_freeway_cars = max_was
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	if police:
		police.set("enabled", police_was)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_freeway() -> void:
	for c in _traffic.freeway_cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.freeway_cars.clear()


## The schedule: the same answer twice, shares near the odds, every incident clear of the ramps
## on its carriageway and of the route's ends, the stall's timings in order and inside its slot.
func _schedule() -> void:
	var seed := _plan.seed
	var same := true
	var kinds := {}
	var bad_site := 0
	var bad_time := 0
	var total := 0
	for ri in _fw.routes.size():
		var zones := ceili(_fw.length_of(ri) / FreewayIncidents.ZONE)
		for zone in zones:
			for dir: int in [1, -1]:
				for slot in range(100, 140):
					var a := FreewayIncidents.incident(_fw, seed, ri, zone, dir, slot)
					var b := FreewayIncidents.incident(_fw, seed, ri, zone, dir, slot)
					if a != b:
						same = false
					total += 1
					if a.is_empty():
						continue
					kinds[int(a.kind)] = int(kinds.get(int(a.kind), 0)) + 1
					if float(a.t) < FreewayIncidents.END_KEEP or float(a.t) > _fw.length_of(ri) - FreewayIncidents.END_KEEP:
						bad_site += 1
					var slot_start := float(slot) * FreewayIncidents.PERIOD - FreewayIncidents.h01([seed, ri, zone, dir, "fwi_phase"]) * FreewayIncidents.PERIOD
					if float(a.start) < slot_start or float(a.end) > slot_start + FreewayIncidents.PERIOD:
						bad_time += 1
					if int(a.kind) == FreewayIncidents.Kind.STALL and not (float(a.patrol) > 0.0 and float(a.tow) > float(a.patrol)):
						bad_time += 1
	_check(same, "freeway incidents: the schedule is pure (the same slot twice)")
	var stall := float(kinds.get(FreewayIncidents.Kind.STALL, 0)) / maxf(float(total), 1.0)
	var debris := float(int(kinds.get(FreewayIncidents.Kind.TYRE, 0)) + int(kinds.get(FreewayIncidents.Kind.MATTRESS, 0))) / maxf(float(total), 1.0)
	_check(stall > 0.12 and stall < 0.28 and debris > 0.1 and debris < 0.28, "freeway incidents: stalls %.2f and debris %.2f of the slots (odds 0.20 / 0.18)" % [stall, debris])
	_check(bad_site == 0 and bad_time == 0, "freeway incidents: every incident inside its route and its slot (%d off the ends, %d out of time)" % [bad_site, bad_time])
	# Running ones: never by a ramp of their own carriageway.
	var by_ramp := 0
	var running := 0
	for c in 12:
		for ri in _fw.routes.size():
			for inc: Dictionary in FreewayIncidents.running(_fw, seed, ri, 0.0, _fw.length_of(ri), 3000.0 + float(c) * 211.0):
				if inc.has("forced"):
					continue
				running += 1
				if not FreewayIncidents.site_ok(_fw, ri, float(inc.t), int(inc.dir)):
					by_ramp += 1
	_check(running > 6 and by_ramp == 0, "freeway incidents: something is always happening somewhere (%d over 12 clocks), never by a ramp (%d)" % [running, by_ramp])
	# The message signs: a share of the gantries, pure.
	var cms := 0
	var gantries := 0
	var every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	for ri in _fw.routes.size():
		var n := (_fw.routes[ri].points as PackedVector2Array).size()
		for idx in range(0, n - 1, every):
			for side: float in [1.0, -1.0]:
				gantries += 1
				if FreewayIncidents.has_cms(seed, ri, idx, side):
					cms += 1
	var share := float(cms) / maxf(float(gantries), 1.0)
	_check(share > 0.2 and share < 0.5, "freeway incidents: %d of %d gantry carriageways carry a message sign (%.2f)" % [cms, gantries, share])


## The stall's script, pure: on the shoulder from the start, the patrol car parked behind it, the
## tow parked ahead, its bed down and the car winched on, then everyone off down the road.
func _stall_script() -> void:
	var inc := {"patrol": 30.0, "tow": 100.0}
	var halves := [2.3, 2.5, 4.7]
	var coast := FreewayIncidents.stall_pose(inc, -6.0, halves)
	var parked := FreewayIncidents.stall_pose(inc, 80.0, halves)
	var tow_stop := 100.0 + FreewayIncidents.TOW_DRIVE
	var winch_mid := FreewayIncidents.stall_pose(inc, tow_stop + 1.0 + FreewayIncidents.BED_SECONDS + FreewayIncidents.WINCH_SECONDS * 0.5, halves)
	var leave_at := tow_stop + 1.0 + FreewayIncidents.BED_SECONDS * 2.0 + FreewayIncidents.WINCH_SECONDS + 4.0
	var leaving := FreewayIncidents.stall_pose(inc, leave_at + 10.0, halves)
	var coast_ok := coast.has("car") and float(coast.car[0]) < -5.0 and float(coast.car[2]) > 2.0 and not coast.has("patrol")
	_check(coast_ok, "freeway incidents: a stalling car coasts in behind its spot (%s)" % str(coast.get("car")))
	var p_ok := parked.has("patrol") and float(parked.patrol[0]) < -(2.3 + 2.5) and float(parked.patrol[2]) == 0.0 and float(parked.patrol[1]) == 1.0 and bool(parked.driver) and bool(parked.patrol_lights)
	_check(p_ok, "freeway incidents: the patrol car parks on the shoulder behind, lights on, the driver out (%s)" % str(parked.get("patrol")))
	var w_ok := winch_mid.has("tow") and float(winch_mid.tow[0]) > 2.3 + 4.7 and float(winch_mid.bed) == 1.0 and bool(winch_mid.loaded) and float(winch_mid.winch) > 0.3 and float(winch_mid.winch) < 0.7
	_check(w_ok, "freeway incidents: the tow parks ahead, bed down, winching the car on (%s bed %s winch %s)" % [str(winch_mid.get("tow")), str(winch_mid.get("bed")), str(winch_mid.get("winch"))])
	var l_ok := leaving.has("tow") and float(leaving.tow[2]) > 5.0 and float(leaving.bed) == 0.0 and bool(leaving.loaded) and not bool(leaving.driver)
	_check(l_ok, "freeway incidents: the tow drives off with its bed level and the car aboard (%s)" % str(leaving.get("tow")))


## The kit: the tread and the mattress inside their budgets and at their real size; the message
## sign's lettering.
func _kit() -> void:
	var worst := 0
	var sizes_ok := true
	for v in 6:
		var m := FreewayIncidentKit.tread_mesh(v)
		var tris := m.surface_get_array_len(0) / 3
		worst = maxi(worst, tris)
		var box := m.get_aabb()
		if box.size.x > 0.45 or box.size.z > 1.9 or box.size.z < 0.4 or box.size.y > 0.6:
			sizes_ok = false
	_check(worst > 300 and worst < 3500 and sizes_ok, "freeway incidents: tyre tread pieces built at size, %d triangles at most" % worst)
	var mat := FreewayIncidentKit.mattress_mesh(0)
	var mbox := mat.get_aabb()
	var mtris := mat.surface_get_array_len(0) / 3
	_check(absf(mbox.size.x - FreewayIncidentKit.MATTRESS.x) < 0.1 and absf(mbox.size.z - FreewayIncidentKit.MATTRESS.z) < 0.1 and mtris < 2500,
		"freeway incidents: a queen mattress, %.2f x %.2f m, %d triangles" % [mbox.size.x, mbox.size.z, mtris])
	var tex := FreewayIncidentKit.cms_texture(["STALLED VEHICLE", "RIGHT SHOULDER", "1 MILE AHEAD"])
	var img := tex.get_image()
	var c := FreewayIncidentKit.cms_cells()
	var lit := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r > 0.5:
				lit += 1
	_check(img.get_width() == c.x and img.get_height() == c.y and lit > 300 and lit < 1400, "freeway incidents: the message sign's LEDs spell three lines (%d x %d, %d lit)" % [img.get_width(), img.get_height(), lit])


## A spot near the middle of a long route that site_ok() accepts on both carriageways.
func _spot() -> Array:
	var best := []
	for ri in _fw.routes.size():
		var len := _fw.length_of(ri)
		if len < 2500.0:
			continue
		var t := len * 0.45
		while t < len * 0.75:
			if FreewayIncidents.site_ok(_fw, ri, t, 1) and FreewayIncidents.site_ok(_fw, ri, t, -1):
				return [ri, t]
			t += 37.0
	return best


func _hover(at: Vector3) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = _ws.to_local(at + Vector3(0.0, 35.0, 0.0))


## A forced stall: its vehicles and driver built, placed where the script says, the CMS behind it
## telling of it, the slow lane moving over, then the tow loading the car and leaving with it.
func _live_stall(node: FreewayIncidents) -> void:
	var spot := _spot()
	if spot.is_empty():
		_check(false, "freeway incidents: a long route with room for a stall")
		return
	var ri: int = spot[0]
	var t: float = spot[1]
	var at := FreewayIncidents.deck_point(_fw, ri, t, 0.0)
	_hover(at)
	_city.update_streaming(true)
	await _ticks(3)
	FreewayIncidents.clear_forced()
	var inc := FreewayIncidents.force(_fw, ri, t, 1, FreewayIncidents.Kind.STALL, 60.0)
	node._update_live(_fw)
	await _ticks(4)
	var entry: Dictionary = node._live.get(FreewayIncidents.key_of(inc), {})
	var sc: Dictionary = entry.get("scene", {})
	var car: Variant = sc.get("car")
	var patrol: Variant = sc.get("patrol")
	var tow: Variant = sc.get("tow")
	var built := car != null and patrol != null and tow != null and is_instance_valid(car) and is_instance_valid(patrol) and is_instance_valid(tow)
	_check(built, "freeway incidents: a stall builds its car, a patrol car and a tow truck")
	if not built:
		return
	await _ticks(2)
	var drv: Variant = sc.get("driver")
	_check(drv != null and is_instance_valid(drv), "freeway incidents: the stalled car's driver stands on the shoulder")
	var shoulder := FreewayIncidents.shoulder_lat(_fw, ri, 1)
	var cp := _ws.to_world((car as Node3D).global_position) as Vector3
	var expect := FreewayIncidents.deck_point(_fw, ri, t, shoulder)
	var pp := _ws.to_world((patrol as Node3D).global_position) as Vector3
	var behind := (Vector2(pp.x, pp.z) - Vector2(at.x, at.z)).dot((_fw.point_at(ri, t)[1] as Vector2)) < -3.0
	_check(Vector2(cp.x, cp.z).distance_to(Vector2(expect.x, expect.z)) < 0.6 and absf(cp.y - expect.y) < 1.5 and behind and (patrol as Node3D).visible,
		"freeway incidents: the car stands on the shoulder (%.2f m off) with the patrol car behind it" % Vector2(cp.x, cp.z).distance_to(Vector2(expect.x, expect.z)))
	_check(int((car as Vehicle).light_signal) == 2 or (car as Vehicle).traffic.get("hazard", false), "freeway incidents: the stalled car's hazards are on")
	_check((patrol as FreewayPatrol).lights_on, "freeway incidents: the patrol car's light bar flashes at the scene")
	_check(not (tow as Node3D).visible, "freeway incidents: the tow truck is not there yet")
	# A CMS behind it on that carriageway tells of it.
	var told := false
	var every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	var idx := (int((t - 300.0) / Freeway.STEP) / every) * every
	while idx > 0 and idx * Freeway.STEP > t - 4000.0:
		if FreewayIncidents.has_cms(_plan.seed, ri, idx, 1.0) and not node._exit_board(_fw, ri, idx, 1.0):
			var msg: Array = node.cms_message(_fw, ri, idx, 1)
			told = String((msg[0] as Array)[0]) == "STALLED VEHICLE"
			break
		idx -= every
	_check(told or idx <= 0 or idx * Freeway.STEP <= t - 4000.0, "freeway incidents: the message sign behind the stall tells of it")
	# The slow lane moves over (or slows) past it.
	var lane3 := _traffic.place_freeway_car(ri, t - 260.0, 1, -1, 26.0)
	lane3.traffic.ai = true
	lane3.traffic.li = Freeway.LANES - 1
	lane3.traffic.lane = Freeway.lane_fraction(float(_fw.routes[ri].width), Freeway.LANES - 1)
	var swerves := int(FreewayIncidents.counts.get("swerve", 0))
	var moved := false
	var slowest := INF
	for i in 60 * 14:
		await _tree.physics_frame
		_hover(at)
		if not is_instance_valid(lane3):
			break
		var tt: Dictionary = lane3.traffic
		if absf(float(tt.t) - t) < 12.0:
			slowest = minf(slowest, float(tt.get("v", 99.0)))
			if TrafficAI.fw_lane(_fw, tt) != Freeway.LANES - 1 or tt.has("lc_from"):
				moved = true
		if float(tt.t) > t + 30.0:
			break
	moved = moved or int(FreewayIncidents.counts.get("swerve", 0)) > swerves
	_check(moved or slowest < 26.0 * FreewayIncidents.SOFT_CAP + 1.0, "freeway incidents: a car in the slow lane moves over past the stall, or slows (moved %s, slowest %.1f m/s)" % [moved, slowest if slowest < INF else -1.0])
	# The tow: on its way in the slow lane, then parked ahead, bed down, the car winched on, away.
	var e_arrive := float(inc.tow) + FreewayIncidents.TOW_DRIVE
	_jump(inc, e_arrive + 1.0 + FreewayIncidents.BED_SECONDS + FreewayIncidents.WINCH_SECONDS * 0.6)
	await _ticks(3)
	var bed := ServiceVehicles.gear_of(tow) as ServiceVehicles.TowBed
	var tp := _ws.to_world((tow as Node3D).global_position) as Vector3
	var ahead := (Vector2(tp.x, tp.z) - Vector2(at.x, at.z)).dot((_fw.point_at(ri, t)[1] as Vector2)) > 4.0
	_check((tow as Node3D).visible and ahead and bed != null and bed.u > 0.95, "freeway incidents: the tow truck parks ahead of the car with its bed down (ahead %s, bed %.2f)" % [ahead, bed.u if bed else -1.0])
	_jump(inc, e_arrive + 1.0 + FreewayIncidents.BED_SECONDS * 2.0 + FreewayIncidents.WINCH_SECONDS + 2.0)
	await _ticks(3)
	var on_bed := (car as Node3D).global_position.distance_to(bed.deck(0.0).origin) < 1.2 if bed else false
	_check(on_bed and int(FreewayIncidents.counts.get("tow_loaded", 0)) > 0, "freeway incidents: the car rides the tow's bed once winched on (%.2f m from its deck)" % ((car as Node3D).global_position.distance_to(bed.deck(0.0).origin) if bed else -1.0))
	_check(sc.get("driver") == null or not is_instance_valid(sc.get("driver")), "freeway incidents: the driver has gone (in the tow's cab)")
	var tp0 := (tow as Node3D).global_position
	_jump(inc, e_arrive + 1.0 + FreewayIncidents.BED_SECONDS * 2.0 + FreewayIncidents.WINCH_SECONDS + 4.0 + 10.0)
	await _ticks(3)
	_check((tow as Node3D).global_position.distance_to(tp0) > 30.0 and (car as Node3D).global_position.distance_to(bed.deck(0.0).origin) < 1.2,
		"freeway incidents: the tow drives off with the car on its bed (%.0f m)" % (tow as Node3D).global_position.distance_to(tp0))
	# Over: the scene is cleared.
	_jump(inc, float(inc.end) - float(inc.start) + 5.0)
	await _ticks(2)
	node._update_live(_fw)
	await _ticks(2)
	var tow_on: bool = is_instance_valid(tow) and _traffic.freeway_cars.has(tow)
	var car_aboard: bool = is_instance_valid(car) and (car as Node).get_parent() == tow
	var patrol_on: bool = not is_instance_valid(patrol) or _traffic.freeway_cars.has(patrol) or (patrol as Node).is_queued_for_deletion()
	_check(tow_on and car_aboard and patrol_on and int(FreewayIncidents.counts.get("handover_tow", 0)) > 0,
		"freeway incidents: when it is over the tow (the car aboard) and the patrol car drive on as freeway traffic (tow %s, car aboard %s, patrol %s)" % [tow_on, car_aboard, patrol_on])
	FreewayIncidents.clear_forced()


func _jump(inc: Dictionary, e: float) -> void:
	var dur := float(inc.end) - float(inc.start)
	inc.start = FreewayIncidents.clock - e
	inc.end = float(inc.start) + dur


## A mattress in lane 1: a car in that lane changes lanes round it, never drives through it; a
## spawn there is moved to a clear lane.
func _mattress_swerve(node: FreewayIncidents) -> void:
	var spot := _spot()
	if spot.is_empty():
		return
	var ri: int = spot[0]
	var t: float = spot[1]
	var at := FreewayIncidents.deck_point(_fw, ri, t, 0.0)
	_hover(at)
	FreewayIncidents.clear_forced()
	var inc := FreewayIncidents.force(_fw, ri, t, 1, FreewayIncidents.Kind.MATTRESS, 5.0, 1)
	node._update_live(_fw)
	await _ticks(3)
	var entry: Dictionary = node._live.get(FreewayIncidents.key_of(inc), {})
	var root: Variant = entry.get("scene", {}).get("debris")
	var placed := false
	if root != null and is_instance_valid(root) and (root as Node).get_child_count() > 0:
		var mp := _ws.to_world(((root as Node).get_child(0) as Node3D).global_position) as Vector3
		var want := FreewayIncidents.deck_point(_fw, ri, t, FreewayIncidents.lane_lat(_fw, ri, 1, 1))
		placed = Vector2(mp.x, mp.z).distance_to(Vector2(want.x, want.z)) < 1.0 and absf(mp.y - want.y) < 0.4
	_check(placed, "freeway incidents: the mattress lies in its lane on the deck")
	_check(FreewayIncidents.spawn_lane(ri, t - 40.0, 1, 1) != 1 and FreewayIncidents.spawn_lane(ri, t - 40.0, 1, 3) == 3,
		"freeway incidents: a spawn by the mattress is moved out of its lane, one elsewhere is not")
	var car := _traffic.place_freeway_car(ri, t - 220.0, 1, -1, 26.0)
	car.traffic.ai = true
	car.traffic.li = 1
	car.traffic.lane = Freeway.lane_fraction(float(_fw.routes[ri].width), 1)
	var through := false
	var changed := false
	for i in 60 * 14:
		await _tree.physics_frame
		_hover(at)
		if not is_instance_valid(car):
			break
		var tt: Dictionary = car.traffic
		changed = changed or tt.has("lc_from") or TrafficAI.fw_lane(_fw, tt) != 1
		if TrafficAI.fw_lane(_fw, tt) == 1 and not tt.has("lc_from") and absf(float(tt.t) - t) < 2.0 + float(tt.half):
			through = true
		if float(tt.t) > t + 40.0:
			break
	_check(changed and not through, "freeway incidents: a car changes lanes round a mattress in its lane (changed %s, through it %s)" % [changed, through])
	# Whatever it does, a car in the mattress's lane never reaches it.
	_clear_freeway()
	var stuck := _traffic.place_freeway_car(ri, t - 120.0, 1, -1, 20.0)
	stuck.traffic.ai = true
	stuck.traffic.li = 1
	stuck.traffic.lane = Freeway.lane_fraction(float(_fw.routes[ri].width), 1)
	var gap_least := INF
	for i in 60 * 10:
		await _tree.physics_frame
		_hover(at)
		var tt: Dictionary = stuck.traffic
		if TrafficAI.fw_lane(_fw, tt) == 1 and not tt.has("lc_from"):
			gap_least = minf(gap_least, (t - 2.0) - (float(tt.t) + float(tt.half)))
	_check(gap_least > -0.5, "freeway incidents: a car in the mattress's lane never reaches it (closest %.1f m)" % (gap_least if gap_least < INF else 99.0))
	FreewayIncidents.clear_forced()


## A slowdown: a car driving into it slows to a crawl, and speeds up again past it. With the switch
## off the hook changes nothing.
func _slowdown(node: FreewayIncidents) -> void:
	var spot := _spot()
	if spot.is_empty():
		return
	var ri: int = spot[0]
	var t: float = spot[1]
	var at := FreewayIncidents.deck_point(_fw, ri, t, 0.0)
	_hover(at)
	FreewayIncidents.clear_forced()
	var inc := FreewayIncidents.force(_fw, ri, t, 1, FreewayIncidents.Kind.SLOW, 5.0)
	node._update_live(_fw)
	await _ticks(2)
	var car := _traffic.place_freeway_car(ri, t - 150.0, 1, -1, 26.0)
	var slowest := INF
	for i in 60 * 14:
		await _tree.physics_frame
		_hover(at)
		if float(car.traffic.t) > t + 20.0:
			slowest = minf(slowest, float(car.traffic.get("v", 99.0)))
	_check(slowest < 26.0 * FreewayIncidents.SLOW_MAX + 0.5, "freeway incidents: a slowdown slows the cars in it (slowest %.1f m/s)" % slowest)
	FreewayIncidents.enabled = false
	var same := FreewayIncidents.drive(_traffic, _fw, car, 21.0, {}, 0.016) == 21.0 and not FreewayIncidents.has_cms(_plan.seed, ri, 0, 1.0) \
		and FreewayIncidents.spawn_lane(ri, t, 1, 1) == 1
	FreewayIncidents.enabled = true
	_check(same, "freeway incidents: with FREEWAY_INCIDENTS off the hooks change nothing")
	FreewayIncidents.clear_forced()
	await _ticks(1)
	node._update_live(_fw)
