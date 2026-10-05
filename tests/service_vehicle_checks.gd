extends RefCounted
## The city's working vehicles (ServiceVehicles, ServiceFleet, KerbBins) for tests/smoke_test.gd.
## Loaded at run time (not named there), so it compiles after the autoloads. Checks: the five
## bodies build as models with their moving parts and gear, inside a build budget; the carts'
## plan is pure, stands in the gutter on a stall line, the streets' days are a hash, long parked
## cars keep off a set; the garbage truck's arm runs a whole cycle (out, the cart taken off the
## kerb, up and over the hopper upside down, back down and set back where it stood); a truck sent
## down a street with its carts out stops at a cart of its colour and empties it; a delivery van
## stops in its lane with its hazards on; the sweeper's brooms spin; the ice-cream truck's chime
## loops and its flashers light while it stands; a tow truck sent for a burnt-out wreck winches it
## onto its bed and carries it off, and the wreck goes with it; the sounds exist.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _fleet: ServiceFleet
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_fleet = city.get_node_or_null("ServiceFleet") as ServiceFleet
	_check(_fleet != null, "the city has a ServiceFleet node")
	if _fleet == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	var was_enabled := ServiceFleet.enabled
	ServiceFleet.enabled = false
	_traffic.staged = true
	_clear_traffic()

	await _builds()
	_sounds()
	var spot := _find_bins()
	_check(not spot.is_empty(), "some house block has its carts planned (KerbBins)")
	if not spot.is_empty():
		var sc := KerbBins.cart_pos(_plan, spot.set, 1)
		print("SERVICE carts at %.1f,%.1f (weekday %d)" % [sc.x, sc.y, int(spot.weekday)])
		_bins_plan(spot)
		await _go(player, spot)
		await _arm_cycle(spot)
		await _collect(spot)
		await _delivery(player)
		await _sweeper(player)
		await _ice_cream(player)
		await _tow(player)

	for c in _made:
		if is_instance_valid(c):
			(c as Node).queue_free()
	_made.clear()
	_clear_traffic()
	_traffic.staged = false
	ServiceFleet.enabled = was_enabled
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()
	_fleet._tend(0.0)


## Off the street into the pool, out of the traffic's list first (as TrafficManager._maintain()
## does): a pooled car still in the list comes back as its own leader.
func _retire(car: Vehicle) -> void:
	_traffic.cars.erase(car)
	_traffic._retire(car)


func _builds() -> void:
	var holder := Node3D.new()
	_city.add_child(holder)
	_made.append(holder)
	var why := ""
	var slowest := 0.0
	for type: int in ServiceVehicles.TYPES:
		var t0 := Time.get_ticks_usec()
		var car := BigVehicles.make(type, 7)
		car.position = Vector3(0.0, 400.0 + float(type), 0.0)
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 2.0, "speed": 0.0}
		car.freeze = true
		holder.add_child(car)
		slowest = maxf(slowest, float(Time.get_ticks_usec() - t0) / 1000.0)
		var name: String = Vehicle.BODY_NAMES[type]
		var gear := ServiceVehicles.gear_of(car)
		var ok := car._has_model and car._wheel_rigs.size() >= 4 and str(car.get_meta("fleet", "")) != ""
		match type:
			ServiceVehicles.GARBAGE:
				var arm := gear as ServiceVehicles.GarbageArm
				ok = ok and arm != null and arm.boom != null and arm.lift != null and arm.lift.get_parent() == arm.boom
			ServiceVehicles.SWEEPER:
				var sw := gear as ServiceVehicles.SweeperGear
				ok = ok and sw != null and sw.brush_r != null and sw.brush_l != null and sw.broom != null
			ServiceVehicles.TOW:
				var bed := gear as ServiceVehicles.TowBed
				ok = ok and bed != null and bed.bed != null
			ServiceVehicles.ICE_CREAM:
				var ic := gear as ServiceVehicles.IceCreamGear
				ok = ok and ic != null and ic.chime != null and not ic._beacon_surfaces.is_empty()
			ServiceVehicles.DELIVERY:
				ok = ok and gear == null
		var holder_node := car.get_node_or_null("BodyModel") as Node3D
		if holder_node != null and holder_node.get_child_count() > 0:
			var sc := (holder_node.get_child(0) as Node3D).scale.x
			# The model is drawn at its own size: its length is _dims()'s.
			if absf(sc - 1.0) > 0.03:
				ok = false
				why += " %s(scale %.3f)" % [name, sc]
		if not ok:
			why += " %s(model %s rigs %d gear %s)" % [name, car._has_model, car._wheel_rigs.size(), gear]
		# A hit hands it to physics like any traffic car.
		if type == ServiceVehicles.TOW:
			car.take_hit(-1, 10.0, Vector3.FORWARD, Vector3.INF, Vehicle.HIT_BULLET)
			_check(not car.is_traffic() and not car.freeze, "a tow truck that is shot leaves the traffic for physics")
	_check(why == "", "the garbage truck, sweeper, tow truck, ice-cream truck and delivery van build as models with their gear%s" % why)
	_check(slowest < 1500.0, "a service vehicle builds in %.0f ms" % slowest)
	await _ticks(2)


func _sounds() -> void:
	var why := ""
	for n: String in ["chime", "hydraulic", "bang", "brush", "winch"]:
		var s := ServiceSounds.stream(n)
		if s == null or s.data.is_empty():
			why += " " + n
	var chime := ServiceSounds.stream("chime")
	_check(why == "", "the service vehicles' sounds are made%s" % why)
	_check(chime != null and chime.loop_mode == AudioStreamWAV.LOOP_FORWARD and chime.data.size() / 2 > ServiceSounds.RATE * 8,
			"the ice-cream chime is a loop of the whole tune")


## A house block with carts, a weekday their street has them out, and the set nearest the middle
## of its run: {"set", "weekday"}.
func _find_bins() -> Dictionary:
	for r in range(0, 40):
		for bz in range(-r, r + 1):
			for bx in range(-r, r + 1):
				if maxi(absi(bx), absi(bz)) != r:
					continue
				var sets := KerbBins.block_sets(_plan, bx, bz)
				if sets.size() < 3:
					continue
				for st: Dictionary in sets:
					for day in 7:
						if KerbBins.street_out(_plan, int(st.axis), int(st.index), day):
							return {"set": st, "weekday": day, "block": Vector2i(bx, bz)}
	return {}


func _bins_plan(spot: Dictionary) -> void:
	var st: Dictionary = spot.set
	var b: Vector2i = spot.block
	var again := KerbBins._plan_block(_plan, b.x, b.y)
	_check(again.size() == KerbBins.block_sets(_plan, b.x, b.y).size(), "the carts' plan is pure (the same block twice)")
	var axis: int = st.axis
	var index: int = st.index
	var w := _plan.road_width(axis, index)
	var off := absf(float(st.lateral) - _plan.road_pos(axis, index))
	_check(off < w * 0.5 and off > w * 0.5 - CityPlan.PARKING_LANE * 0.5, "a cart set stands in the gutter (%.2f of %.2f from the centre line)" % [off, w * 0.5])
	var snapped := KerbBins.snap_to_stall(_plan, axis, index, float(st.along))
	_check(absf(snapped - float(st.along)) < 0.01, "a cart set stands on a stall line between two parking bays")
	var outs := 0
	for i in 200:
		if KerbBins.street_out(_plan, 0, i, 2):
			outs += 1
	_check(outs > 40 and outs < 120, "about %d%% of streets have their carts out on a day (%d of 200)" % [KerbBins.OUT_PERCENT, outs])
	var c := KerbBins.cart_pos(_plan, st, 1)
	var bay := Vector3(c.x, 0.0, c.y)
	_check(KerbBins.blocks_parking(_plan, bay, 6.1) and not KerbBins.blocks_parking(_plan, bay, 4.9),
			"a long parked car keeps off a cart set, an ordinary one fits between")
	# Sweeping days: a share of streets a day, never a collection street, nothing parks along one.
	var swept := 0
	var clash := 0
	var swept_road := -1
	for i in 200:
		if KerbBins.swept(_plan, 0, i, 3):
			swept += 1
			swept_road = i
			if KerbBins.street_out(_plan, 0, i, 3):
				clash += 1
	_check(swept > 8 and swept < 45 and clash == 0, "about %d%% of streets are swept on a day, none a collection street (%d of 200)" % [KerbBins.SWEEP_PERCENT, swept])
	if swept_road >= 0:
		var was_day := KerbBins.weekday
		KerbBins.weekday = 3
		var x := _plan.road_pos(CityPlan.AXIS_X, swept_road) + CityPlan.parking_offset(_plan.road_width(CityPlan.AXIS_X, swept_road))
		var z := (_plan.road_pos(CityPlan.AXIS_Z, 0) + _plan.road_pos(CityPlan.AXIS_Z, 1)) * 0.5
		_check(KerbBins.blocks_parking(_plan, Vector3(x, 0.0, z), 4.5), "nothing parks along a street swept today")
		KerbBins.weekday = was_day
	var colors := {}
	for k in 3:
		colors[KerbBins.cart_color(st, k)] = true
	_check(colors.size() == 3, "a set is one cart of each colour")


## The player to the cart set's street (the fleet draws the carts round the player).
func _go(player: Player, spot: Dictionary) -> void:
	_fleet.weekday = int(spot.weekday)
	_fleet._collected.clear()
	_fleet._picked.clear()
	var st: Dictionary = spot.set
	var c := KerbBins.cart_pos(_plan, st, 1)
	var side := float(st.side)
	var pavement := Vector2(c.x + side * 3.0, c.y) if int(st.axis) == CityPlan.AXIS_X else Vector2(c.x, c.y + side * 3.0)
	player.global_position = _ws.to_local(Vector3(pavement.x, _plan.height_at(pavement) + 2.0, pavement.y))
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(3)
	_fleet._survey_bins()
	_fleet._draw_bins()
	var found := false
	for e: Array in _fleet.shown:
		if int((e[0] as Dictionary).id) == int(st.id):
			found = true
	_check(found and _fleet._bins_near.multimesh.instance_count > 0, "the carts are drawn at the kerb round the player (%d near)" % _fleet._bins_near.multimesh.instance_count)
	# A blast by another set's carts throws them (debris) and they stay gone today.
	var other := {}
	for e: Array in _fleet.shown:
		if int((e[0] as Dictionary).id) != int(st.id):
			other = e[0]
	if not other.is_empty():
		var bc := KerbBins.cart_pos(_plan, other, 1)
		var props_before := _tree.get_nodes_in_group("physics_prop").size()
		Explosion.last_blast_world = Vector3(bc.x, _plan.height_at(bc), bc.y)
		Explosion.blast_count += 1
		_fleet._knock_carts()
		var knocked := _fleet._knocked.has(int(other.id) * 3 + 1)
		var thrown := _tree.get_nodes_in_group("physics_prop").size() - props_before
		_check(knocked and thrown >= 1, "a blast throws the carts beside it as bodies (%d thrown)" % thrown)
		_fleet._draw_bins()


## The arm alone: a truck stood beside a cart, one whole cycle stepped by hand.
func _arm_cycle(spot: Dictionary) -> void:
	var st: Dictionary = spot.set
	var axis: int = st.axis
	var dir := int(-float(st.side)) if axis == CityPlan.AXIS_X else int(float(st.side))
	var c := KerbBins.cart_pos(_plan, st, 0)
	var a := c.y if axis == CityPlan.AXIS_X else c.x
	var car := _fleet._place(ServiceVehicles.GARBAGE, axis, int(st.index), dir, a - dir * ServiceVehicles.ARM_AHEAD, 0.0)
	if car == null:
		# Too near the player for the fleet's own placement rule: put it down directly.
		var lanes := 2 if _plan.road_width(axis, int(st.index)) > _plan.street_width + 1.0 else 1
		car = _traffic.place_car(axis, int(st.index), dir, lanes - 1, a - dir * ServiceVehicles.ARM_AHEAD, 0.0, false, ServiceVehicles.GARBAGE)
	_check(car != null, "a garbage truck is put down beside a cart")
	if car == null:
		return
	# Pulled to the kerb as it would be at a stop.
	car.traffic.shift = _fleet.kerb_shift
	car.traffic.v = 0.0
	await _ticks(3)
	var arm := ServiceVehicles.gear_of(car) as ServiceVehicles.GarbageArm
	var key := int(st.id) * 3
	var picked := [false, false]
	var xf := _fleet.cart_xform(st, 0)
	var began := arm != null and arm.begin(xf, KerbBins.cart_color(st, 0),
			func() -> void: picked[0] = true; _fleet._cart_taken(key),
			func() -> void: picked[1] = true; _fleet._cart_back(key))
	_check(began, "the arm reaches the cart from the kerb lane (ext %.2f)" % (arm.target_ext if arm else -1.0))
	if not began:
		_retire(car)
		return
	var top := -INF
	var flipped := false
	var road_y := xf.origin.y
	var hidden := false
	for i in 900:
		arm.advance(1.0 / 60.0)
		if arm.cart != null and is_instance_valid(arm.cart):
			var cy := arm.cart.global_position.y - road_y
			top = maxf(top, cy)
			if arm.cart.global_basis.y.y < -0.6:
				flipped = true
			if _fleet._picked.has(key):
				_fleet._draw_bins()
				hidden = true
				for e: Array in _fleet.shown:
					if int((e[0] as Dictionary).id) == int(st.id) and int(e[1]) == 0:
						hidden = false
		if not arm.busy():
			break
	_check(picked[0] and picked[1] and not arm.busy(), "the arm runs a whole cycle: the cart taken and set back (%d cycles)" % arm.cycles)
	_check(top > 2.4 and flipped, "the cart goes up over the hopper and is tipped upside down (%.2f m up)" % top)
	_check(hidden and not _fleet._picked.has(key), "the kerb's cart is hidden while the arm holds it and back after")
	_check(arm.ext < 0.01 and absf(arm.theta) < 0.01, "the arm folds back to rest")
	_retire(car)
	_fleet._tend(0.0)


## A truck sent down the street stops at a cart of its colour and empties it.
func _collect(spot: Dictionary) -> void:
	var st: Dictionary = spot.set
	var axis: int = st.axis
	var dir := int(-float(st.side)) if axis == CityPlan.AXIS_X else int(float(st.side))
	var c := KerbBins.cart_pos(_plan, st, 1)
	var a := c.y if axis == CityPlan.AXIS_X else c.x
	var stream := KerbBins.cart_color(st, 1)
	var lanes := 2 if _plan.road_width(axis, int(st.index)) > _plan.street_width + 1.0 else 1
	var car := _traffic.place_car(axis, int(st.index), dir, lanes - 1, a - dir * 9.0, _fleet.garbage_speed, false, ServiceVehicles.GARBAGE)
	_check(car != null, "a garbage truck is sent down the street")
	if car == null:
		return
	ServiceVehicles.gear_of(car).reset()
	_fleet._cars[car.get_instance_id()] = {"car": car, "kind": ServiceVehicles.GARBAGE}
	car.traffic.work = "garbage"
	car.traffic.stream = stream
	var key := int(st.id) * 3 + 1
	var stopped_at := INF
	var lifted := false
	var hazard := false
	for i in 1500:
		await _tree.physics_frame
		if i % 150 == 0 and OS.get_environment("SVC_DEBUG") == "1":
			print("SVC t=%d v=%.2f along=%.2f ws=%s" % [i, float(car.traffic.get("v", -1)), float(car.traffic.get("along", 0)), ServiceFleet.work_stop(car, car.traffic, float(car.traffic.get("along", 0)), 0.0, 0.0)])
		if car.traffic.get("lifting", false):
			lifted = true
			hazard = hazard or car._traffic_signal() == 2
			if is_inf(stopped_at):
				var wp: Vector3 = _ws.to_world(car.global_position)
				var along := wp.z if axis == CityPlan.AXIS_X else wp.x
				stopped_at = absf((along + dir * ServiceVehicles.ARM_AHEAD) - a)
		if _fleet._collected.has(key):
			break
	if not lifted:
		var wp: Vector3 = _ws.to_world(car.global_position)
		var tt: Dictionary = car.traffic.duplicate()
		tt.erase("cart")
		print("SERVICE collect traffic: ", tt, " ws ", ServiceFleet.work_stop(car, car.traffic, (wp.z if axis == CityPlan.AXIS_X else wp.x), 0.0, 0.0))
		print("SERVICE collect: truck at %s along-cart %.2f v %.2f cart %s sets %d work %s" % [wp, ((wp.z if axis == CityPlan.AXIS_X else wp.x) - a) * dir,
				float(car.traffic.get("v", -1.0)), str(car.traffic.get("cart", [])).left(60), _fleet._sets.size(), car.traffic.get("work", "")])
	_check(lifted and stopped_at < 0.9, "the truck stops with its arm at the cart (%.2f m off)" % stopped_at)
	_check(_fleet._collected.has(key), "the truck empties the cart of its colour")
	_check(hazard, "its hazards flash while it lifts")
	_retire(car)
	_fleet._tend(0.0)


func _road_near(player: Player) -> Dictionary:
	var pw: Vector3 = _ws.to_world(player.global_position)
	var ks := StreetRoute.kerb_stop(_plan, Vector2(pw.x, pw.z), 0.0)
	return ks


func _delivery(player: Player) -> void:
	var ks := _road_near(player)
	if ks.is_empty():
		_check(false, "a road near the player for the van")
		return
	var axis: int = ks.axis
	var dir: int = ks.dir
	var lanes := 2 if _plan.road_width(axis, int(ks.index)) > _plan.street_width + 1.0 else 1
	var along := float(ks.along) - dir * 10.0
	var car := _traffic.place_car(axis, int(ks.index), dir, lanes - 1, along, 8.0, false, ServiceVehicles.DELIVERY)
	_check(car != null and car.body_type == ServiceVehicles.DELIVERY, "a delivery van is put on the street")
	if car == null:
		return
	_fleet._cars[car.get_instance_id()] = {"car": car, "kind": ServiceVehicles.DELIVERY}
	car.traffic.work = "delivery"
	car.traffic.next_stop = along + dir * 12.0
	var stood := false
	var flashing := false
	for i in 400:
		await _tree.physics_frame
		if float(car.traffic.get("dwell", 0.0)) > 0.5:
			stood = true
			flashing = car._traffic_signal() == 2
			break
	_check(stood and car.traffic_speed < 0.3, "the delivery van stops in its lane")
	_check(flashing, "the double-parked van runs its hazards")
	_retire(car)
	_fleet._tend(0.0)


func _sweeper(player: Player) -> void:
	var ks := _road_near(player)
	if ks.is_empty():
		return
	var axis: int = ks.axis
	var dir: int = ks.dir
	var lanes := 2 if _plan.road_width(axis, int(ks.index)) > _plan.street_width + 1.0 else 1
	var car := _traffic.place_car(axis, int(ks.index), dir, lanes - 1, float(ks.along) - dir * 30.0, _fleet.sweeper_speed, false, ServiceVehicles.SWEEPER)
	if car == null:
		_check(false, "a sweeper is put on the street")
		return
	_fleet._cars[car.get_instance_id()] = {"car": car, "kind": ServiceVehicles.SWEEPER}
	car.traffic.work = "sweep"
	var g := ServiceVehicles.gear_of(car) as ServiceVehicles.SweeperGear
	var b0 := g.brush_r.basis if g and g.brush_r else Basis()
	for i in 90:
		await _tree.physics_frame
	await _tree.process_frame
	var spun := g != null and g.brush_r != null and not g.brush_r.basis.is_equal_approx(b0)
	_check(g != null and g.working and spun, "the sweeper works its brooms along the kerb")
	_check(absf(float(car.traffic.get("shift", 0.0))) > 0.3, "the sweeper hugs the kerb (shift %.2f)" % float(car.traffic.get("shift", 0.0)))
	_retire(car)
	_fleet._tend(0.0)


func _ice_cream(player: Player) -> void:
	var ks := _road_near(player)
	if ks.is_empty():
		return
	var axis: int = ks.axis
	var dir: int = ks.dir
	var lanes := 2 if _plan.road_width(axis, int(ks.index)) > _plan.street_width + 1.0 else 1
	var along := float(ks.along) - dir * 8.0
	var car := _traffic.place_car(axis, int(ks.index), dir, lanes - 1, along, 4.0, false, ServiceVehicles.ICE_CREAM)
	if car == null:
		_check(false, "an ice-cream truck is put on the street")
		return
	_fleet._cars[car.get_instance_id()] = {"car": car, "kind": ServiceVehicles.ICE_CREAM}
	car.traffic.work = "ice_cream"
	car.traffic.next_stop = along + dir * 8.0
	var g := ServiceVehicles.gear_of(car) as ServiceVehicles.IceCreamGear
	var played := false
	var stood := false
	for i in 400:
		await _tree.physics_frame
		played = played or (g != null and g.chime.playing)
		if g != null and g.standing:
			stood = true
			break
	var lit := false
	if g != null and not g._beacon_surfaces.is_empty():
		var e: Array = g._beacon_surfaces[0]
		var m := (e[0] as MeshInstance3D).get_surface_override_material(int(e[1])) as ShaderMaterial
		lit = m != null and float(m.get_shader_parameter("active")) > 0.5
	_check(played, "the ice-cream truck plays its chime as it drives")
	_check(stood and lit, "it stops with its flashers lit")
	_retire(car)
	_fleet._tend(0.0)


## A burnt-out wreck by the kerb, the player walked away: a tow truck winches it on and leaves.
func _tow(player: Player) -> void:
	var ks := _road_near(player)
	if ks.is_empty():
		return
	var stop: Vector2 = ks.stop
	var dir: int = ks.dir
	var axis: int = ks.axis
	# The wreck in the parking lane beside where the kerb stop is.
	var side := StreetRoute.lane_side(axis, dir)
	var lat := _plan.road_pos(axis, int(ks.index)) + side * CityPlan.parking_offset(_plan.road_width(axis, int(ks.index)))
	var at := Vector2(lat, float(ks.along)) if axis == CityPlan.AXIS_X else Vector2(float(ks.along), lat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var wreck := Vehicle.random_car(rng)
	wreck.position = _ws.to_local(Vector3(at.x, _plan.height_at(at) + 0.6, at.y))
	wreck.rotation.y = 0.0 if axis == CityPlan.AXIS_X else PI * 0.5
	_city.add_child(wreck)
	_made.append(wreck)
	await _ticks(20)
	var dmg := wreck.damage_state()
	dmg.become_wreck()
	dmg.extinguish()
	await _ticks(30)
	# The player well away (the tow waits for that); the truck sent close up the street.
	var pw: Vector3 = _ws.to_world(player.global_position)
	var away := Vector2(pw.x, pw.z) + (Vector2(pw.x, pw.z) - at).normalized() * 60.0
	player.global_position = _ws.to_local(Vector3(away.x, _plan.height_at(away) + 2.0, away.y))
	var back_was := _fleet.spawn_back
	var clear_was := _fleet.spawn_clear
	var bed_was := _fleet.bed_seconds
	var winch_was := _fleet.winch_seconds
	_fleet.spawn_back = Vector2(30.0, 32.0)
	_fleet.spawn_clear = 0.0
	_fleet.bed_seconds = 1.0
	_fleet.winch_seconds = 1.5
	var sent := _fleet.send_tow(wreck)
	_check(sent, "a tow truck is sent for a burnt-out wreck")
	var carried := false
	var e := {}
	for i in 2400:
		await _tree.physics_frame
		e = _fleet.tow_of(wreck)
		if not e.is_empty() and String(e.state) == "carry":
			carried = true
			break
	_check(carried, "the tow truck winches the wreck onto its bed (state %s)" % str(e.get("state", "none")))
	if carried:
		var car: Vehicle = e.car
		var bed := ServiceVehicles.gear_of(car) as ServiceVehicles.TowBed
		var off := wreck.global_position.distance_to(bed.deck(0.0).origin)
		_check(wreck.freeze and wreck.wheels.is_empty() and not wreck.is_in_group("debris") and off < 2.0,
				"the wreck rides the bed, out of the physics and the debris (%.2f m off the deck)" % off)
		for i in 60:
			await _tree.physics_frame
		var moved := car.traffic_speed > 1.0
		_check(moved, "the tow truck drives off with it")
		_retire(car)
		# The fleet ticks its tows in _process: under load several physics steps run inside one
		# rendered frame, so three physics ticks can pass with no tick of the fleet's.
		for i in 30:
			await _tree.process_frame
			if not is_instance_valid(wreck) or wreck.is_queued_for_deletion():
				break
		_check(not is_instance_valid(wreck) or wreck.is_queued_for_deletion(), "the wreck goes when the tow truck leaves")
	_fleet.spawn_back = back_was
	_fleet.spawn_clear = clear_was
	_fleet.bed_seconds = bed_was
	_fleet.winch_seconds = winch_was
