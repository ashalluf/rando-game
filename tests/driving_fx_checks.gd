extends RefCounted
## Driving effects (DrivingFX, scripts/vehicles/driving_fx.gd) for tests/smoke_test.gd. Loaded at
## run time, so it compiles after the autoloads. On a deck 300 m over the street, like the car
## damage, cabin and lamp checks. Checks: the node is made once; a car sliding sideways lays skid
## marks on the skid mark shader, smokes and squeals; the same slide on a soaking street throws
## spray, not smoke, and the marks still go down; the player's burnout (throttle against the
## handbrake) smokes the rear tyres and marks the road while the car stands; on dirt a rolling
## tyre takes a print and throws dust, never smoke; a car on its roof sliding down the deck sparks
## and grinds; the ring of marks wraps without growing and old marks are swept away; a car
## dropped from the watch has its contact reports switched back off; a cold morning puffs the
## player's exhaust; a hard lift-off at speed backfires; the samples are loaded.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3
var _fx: DrivingFX


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	var first := _car(Vector2(-40.0, -20.0))
	await _ticks(3)
	_fx = DrivingFX.instance()
	_check(_fx != null and _fx.is_inside_tree(), "DrivingFX is made by the first car")
	if _fx != null:
		_check(_tree.get_nodes_in_group("vehicle").size() > 0 and _count_fx() == 1, "and only once")
		_check(Sfx.has("skid") and Sfx.has("scrape") and Sfx.has("backfire"), "the squeal, scrape and backfire sounds are loaded")
		first.queue_free()
		# A dry street (earlier checks can leave it wet, and a wet slide throws spray, not smoke).
		var weather: Node = city.get_node_or_null("Weather")
		var hold: Variant = weather.get("_wet_hold") if weather else null
		var wet: Variant = weather.get("wetness") if weather else null
		if weather:
			weather.set("_wet_hold", 0.0)
			weather.set("wetness", 0.0)
		await _drift()
		await _wet_drift(city)
		await _burnout(player)
		await _dirt()
		await _scrape()
		await _ring()
		await _exhaust(player, city)
		await _orphan()
		if weather:
			weather.set("_wet_hold", hold)
			weather.set("wetness", wet)

	if player.is_driving():
		player.exit_vehicle()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _count_fx() -> int:
	return _tree.get_nodes_in_group("driving_fx").size()


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 1.0, 240.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(at: Vector2, upside_down: bool = false) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	car.position = _city.to_local(_top + Vector3(at.x, 2.2 if upside_down else 0.9, at.y))
	if upside_down:
		car.rotation.z = PI
	_city.add_child(car)
	_cars.append(car)
	return car


func _clear() -> void:
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	await _ticks(3)


## Holds a car sliding along `vel` for `n` ticks (the crash watch held: this is not a crash).
func _slide(car: Vehicle, vel: Vector3, n: int, watch: Callable = Callable()) -> void:
	for i in n:
		car.hold_crash_watch(3)
		car.linear_velocity = Vector3(vel.x, car.linear_velocity.y, vel.z)
		await _tree.physics_frame
		if watch.is_valid():
			watch.call()


func _drift() -> void:
	var car := _car(Vector2(-20.0, 0.0))
	await _ticks(40) # settle on the springs
	_fx._scan_left = 0.0
	var marks0 := _fx.marks_alive()
	var smoke := [0]
	var screech := [false]
	var on := [0]
	# Sideways at 12 m/s with a little forward: every tyre slides.
	await _slide(car, car.global_basis.x * 12.0 - car.global_basis.z * 4.0, 40, func():
		smoke[0] = maxi(smoke[0], _fx.last_smoke)
		var lit := 0
		for p in _fx._smoke:
			if p.emitting:
				lit += 1
		on[0] = maxi(on[0], lit)
		for p: AudioStreamPlayer3D in _fx._screech:
			screech[0] = screech[0] or p.playing)
	var laid := _fx.marks_alive() - marks0
	_check(laid >= 10, "a car sliding sideways lays skid marks (%d segments)" % laid)
	_check(_fx._marks_node.material_override is ShaderMaterial and (_fx._marks_node.material_override as ShaderMaterial).shader.resource_path == "res://shaders/skid_mark.gdshader",
			"on the skid mark shader, one MultiMesh")
	_check(smoke[0] > 0, "and smokes (%d tyres asking)" % smoke[0])
	_check(on[0] > 0 and on[0] <= _fx._smoke.size(), "from the pool (%d of %d emitters)" % [on[0], _fx._smoke.size()])
	_check(screech[0], "and squeals")
	# A segment lies on the deck, flat, a tyre wide.
	var i := (_fx._mark_next - 1 + _fx._marks.instance_count) % _fx._marks.instance_count
	var xf := _fx._marks.get_instance_transform(i)
	var y := _fx.to_global(xf.origin).y
	# Under --headless a MultiMesh reads back identity (CLAUDE.md, measurement trap 2): only check
	# where the renderer keeps it.
	if xf.basis != Basis():
		_check(absf(y - _top.y) < 0.08 and absf(xf.basis.x.length() - 0.235) < 0.05,
				"a mark lies on the road, a tyre wide (y %.3f over, width %.3f)" % [y - _top.y, xf.basis.x.length()])
	await _clear()


func _wet_drift(city: Node3D) -> void:
	var weather: Node = city.get_node_or_null("Weather")
	if weather == null:
		return
	weather.set("_wet_hold", 0.85)
	weather.set("wetness", 0.85)
	var car := _car(Vector2(-20.0, 0.0))
	await _ticks(40)
	_fx._scan_left = 0.0
	var marks0 := _fx.marks_alive()
	var smoke := [0]
	var spray := [0]
	await _slide(car, car.global_basis.x * 12.0, 30, func():
		smoke[0] = maxi(smoke[0], _fx.last_smoke)
		spray[0] = maxi(spray[0], _fx.last_dust))
	_check(smoke[0] == 0 and spray[0] > 0, "on a soaking street the slide throws spray, not smoke (smoke %d, spray %d)" % [smoke[0], spray[0]])
	_check(_fx.marks_alive() > marks0, "and still marks the road")
	weather.set("_wet_hold", 0.0)
	weather.set("wetness", 0.0)
	await _clear()


func _burnout(player: Player) -> void:
	# Nothing left held by an earlier check: only the keys this one presses.
	for action in ["move_back", "move_left", "move_right", "boost", "jump", "fire", "alt_fire", "move_forward"]:
		Input.action_release(action)
	var car := _car(Vector2(0.0, -10.0))
	await _ticks(40)
	player.enter_vehicle(car)
	await _ticks(2)
	_fx._scan_left = 0.0
	var marks0 := _fx.marks_alive()
	var rear_smoke := [false]
	Input.action_press("move_forward")
	Input.action_press("alt_fire")
	for i in 50:
		car.hold_crash_watch(3)
		await _tree.physics_frame
		for k in _fx._smoke_keys.size():
			var key: Variant = _fx._smoke_keys[k]
			if key == null:
				continue
			for w in car.wheels:
				if is_instance_valid(w) and w.get_instance_id() == key and w.use_as_traction and w.position.z > 0.0:
					rear_smoke[0] = true
	var moved := car.linear_velocity.length()
	_check(rear_smoke[0], "a burnout (throttle against the handbrake) smokes the rear tyres")
	_check(_fx.marks_alive() > marks0 or moved < 3.0, "and the car stands (%.1f m/s) laying rubber (%d)" % [moved, _fx.marks_alive() - marks0])
	Input.action_release("alt_fire")
	Input.action_release("move_forward")
	# A hard lift-off at speed: full throttle one tick, nothing the next, at 15 m/s, with the
	# chance at 1. Fed to DrivingFX directly, two calls in a row: through the input and the
	# physics ticks the order of the car's and DrivingFX's steps decides which tick sees what.
	var chance := _fx.backfire_chance
	_fx.backfire_chance = 1.0
	_fx._backfire_at = -100.0
	_fx._prev_force.erase(car.get_instance_id())
	car.linear_velocity = -car.global_basis.z * 15.0
	car.engine_force = -car.engine_power * 0.73
	_fx._tick_backfire(car)
	var quiet := _fx._backfire_at < 0.0
	car.engine_force = 0.0
	_fx._tick_backfire(car)
	var popped := _fx._backfire_at > 0.0 and _fx._flame.emitting
	# And no pop from a gentle lift-off.
	_fx._backfire_at = -100.0
	_fx._prev_force.erase(car.get_instance_id())
	car.engine_force = -car.engine_power * 0.2
	_fx._tick_backfire(car)
	car.engine_force = 0.0
	_fx._tick_backfire(car)
	var gentle := _fx._backfire_at < 0.0
	_fx.backfire_chance = chance
	_check(quiet and popped, "a hard lift-off at speed backfires (a flame out of the pipe)")
	_check(gentle, "a gentle one does not")
	player.exit_vehicle()
	await _clear()


func _dirt() -> void:
	_deck.collision_layer = 1 | CityChunk.TERRAIN_LAYER
	var car := _car(Vector2(-20.0, 0.0))
	await _ticks(40)
	_fx._scan_left = 0.0
	var marks0 := _fx.marks_alive()
	var dust := [0]
	var smoke := [0]
	await _slide(car, -car.global_basis.z * 14.0, 30, func():
		dust[0] = maxi(dust[0], _fx.last_dust)
		smoke[0] = maxi(smoke[0], _fx.last_smoke))
	_check(_fx.marks_alive() > marks0, "on dirt a rolling tyre leaves tracks (%d)" % (_fx.marks_alive() - marks0))
	_check(dust[0] > 0 and smoke[0] == 0, "and throws dust, never smoke (dust %d, smoke %d)" % [dust[0], smoke[0]])
	_deck.collision_layer = 1
	await _clear()


func _scrape() -> void:
	var car := _car(Vector2(-20.0, 0.0), true)
	await _ticks(60)
	_fx._scan_left = 0.0
	var sparks := [0]
	var grind := [false]
	await _slide(car, Vector3(14.0, 0.0, 0.0), 30, func():
		sparks[0] = maxi(sparks[0], _fx.last_sparks)
		for p: AudioStreamPlayer3D in _fx._scrape:
			grind[0] = grind[0] or p.playing)
	_check(sparks[0] > 0, "a car sliding on its roof sparks")
	_check(grind[0], "and grinds")
	_check(car.contact_monitor, "while it is watched its contacts are reported")
	# Stopped and far away: dropped from the watch, its contact reports go back off.
	car.linear_velocity = Vector3.ZERO
	car.global_position += Vector3(0.0, 0.0, 400.0)
	_fx._scan_left = 0.0
	await _ticks(3)
	_check(not car.contact_monitor, "and once dropped from the watch they are switched back off")
	await _clear()


func _ring() -> void:
	var cap := _fx._marks.instance_count
	var st := {"last": null}
	var at := _fx.global_position + Vector3(0.0, 300.0, 0.0)
	for i in cap + 200:
		_fx._lay(st, at + Vector3(0.4 * float(i % 40), 0.0, float(i / 40) * 0.01), Vector3.UP, Vector3.RIGHT, 0.24, Color(0.05, 0.05, 0.05), 0.7)
	_check(_fx._mark_count == cap and _fx._marks.visible_instance_count == cap, "the ring of marks wraps at its capacity (%d)" % cap)
	_fx._clock += _fx.mark_life + 5.0
	_fx._mark_sweep = 0.0
	_fx._sweep_marks(0.0)
	_check(_fx.marks_alive() == 0, "and marks past their life are swept away")


func _exhaust(player: Player, city: Node3D) -> void:
	var dn: Node = city.get_node_or_null("DayNight")
	if dn == null:
		return
	var hour: float = dn.get("hour")
	dn.set("hour", 7.0)
	var car := _car(Vector2(0.0, -10.0))
	await _ticks(30)
	player.enter_vehicle(car)
	_fx._scan_left = 0.0
	await _ticks(6)
	var on := false
	for p in _fx._exhaust:
		on = on or p.emitting
	_check(on or _fx._exhaust.is_empty(), "a cold morning puffs the player's exhaust")
	player.exit_vehicle()
	dn.set("hour", hour)
	await _clear()


## A DrivingFX whose deferred add was dropped (its level freed first) is not taken for "made, add
## pending" for ever: the next car makes another. Staged in a disabled holder of its own, so the
## new node never ticks or touches the city's cars, and the real one is put back after.
func _orphan() -> void:
	var real := DrivingFX._inst
	var made := DrivingFX._made_frame
	var holder := Node3D.new()
	holder.name = "DrivingFXOrphanCheck"
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	_tree.root.add_child(holder)
	var fake := DrivingFX.new()
	DrivingFX._inst = fake
	DrivingFX._made_frame = Engine.get_process_frames()
	DrivingFX.ensure(holder)
	var kept := DrivingFX._inst == fake
	DrivingFX._made_frame = Engine.get_process_frames() - 5
	DrivingFX.ensure(holder)
	var remade := not is_instance_valid(fake) and DrivingFX._inst != null
	await _tree.process_frame
	await _tree.process_frame
	var added := DrivingFX._inst != null and is_instance_valid(DrivingFX._inst) and DrivingFX._inst.get_parent() == holder
	_check(kept, "a DrivingFX made this frame and not yet added counts as made")
	_check(remade and added, "one whose add never ran is freed and made again")
	DrivingFX._inst = real
	DrivingFX._made_frame = made
	holder.queue_free()
	await _tree.process_frame
