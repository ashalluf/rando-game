extends RefCounted
## Car damage checks for tests/smoke_test.gd (scripts/vehicles/car_damage.gd). Loaded at run time
## (not named there), so it compiles after the autoloads and can name Vehicle, CarDamage, Police,
## Explosion and PoliceCar freely. Everything happens on a platform 250 m over the street with the
## player standing on it, so no pedestrian, traffic car or building is in the way of the blasts.
## Checks: an undamaged car keeps the shared paint shader and has no damage node; the first hit
## copies its paint onto the damage shader (the shadow twins follow, other cars do not); rounds
## accumulate (holes capped), the engine bay takes more, glass crazes and lamps break (the night
## glow loses them); a crash from the velocity watch dents it and a gentle bump does not; a rocket
## blast sets a car burning on the short fuse, it explodes (the player's crime, a second blast),
## is thrown up and becomes a charred wreck managed as debris, with no NaN; the police's rounds are
## theirs; the wreck and burning caps hold; the driven car throws the player out when it goes up
## and a wreck cannot be driven; a pooled cruiser comes back clean; aircraft take none of it.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _ws: Node
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_ws = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = _ws.to_world(player.global_position)
	var caps := [CarDamage.max_wrecks, CarDamage.max_burning]
	_top = player.global_position + Vector3(0.0, 250.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 34.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _first_hit_and_rounds()
	await _crash()
	await _rocket_to_wreck()
	await _fire_stages()
	await _blame_and_caps()
	await _driven_car(player)
	await _pooled_cruiser()
	_city_cars_clean()
	var jet := Aircraft.new()
	_check(not jet.can_take_damage(), "the flyable jets take no car damage")
	jet.free()

	CarDamage.max_wrecks = caps[0]
	CarDamage.max_burning = caps[1]
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A parked sedan (body type 0) at `x` metres along the deck.
func _car(x: float, type: int = 0) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(x, 0.9, 0.0)
	_cars.append(car)
	return car


func _paint_of(car: Vehicle) -> ShaderMaterial:
	for m in car._body_meshes:
		if not is_instance_valid(m) or String(m.name).ends_with("_far"):
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(si) as ShaderMaterial
			if mat != null and (mat.shader == Vehicle.PAINT_SHADER or mat.shader == CarDamage.PAINT_DAMAGE_SHADER):
				return mat
	return null


## A point on the car's right-hand door (scene space) and the way into it.
func _door(car: Vehicle, z: float = 0.3) -> Array:
	return [car.global_transform * Vector3(0.95, 0.45, z), -car.global_basis.x]


func _first_hit_and_rounds() -> void:
	var a := _car(-20.0)
	var b := _car(-12.0)
	await _ticks(40)
	var ma := _paint_of(a)
	var mb := _paint_of(b)
	_check(a._damage == null and a.get_node_or_null("Damage") == null and ma != null and ma.shader == Vehicle.PAINT_SHADER,
			"an undamaged car has no damage node and wears the shared paint shader")
	var d := _door(a)
	for i in 5:
		a.take_hit(-1, 10.0, d[1], d[0] + a.global_basis.z * 0.05 * i, Vehicle.HIT_BULLET)
	await _tree.process_frame
	var dmg: CarDamage = a._damage
	var pa := _paint_of(a)
	_check(dmg != null and pa != null and pa != ma and pa.shader == CarDamage.PAINT_DAMAGE_SHADER and _paint_of(b) == mb,
			"the first hit copies that car's paint onto the damage shader, and only that car's")
	var twins_ok := not a._body_shadows.is_empty()
	for tw in a._body_shadows:
		if is_instance_valid(tw):
			for si in tw.mesh.get_surface_count():
				var om := tw.get_surface_override_material(si)
				if om == ma:
					twins_ok = false
	_check(twins_ok, "the shadow twins follow the paint onto the damage shader (%d twins)" % a._body_shadows.size())
	_check(dmg != null and is_equal_approx(dmg.health, dmg.max_health - 5.0 * 10.0 * dmg.bullet_scale) and dmg.holes_made == 5,
			"five rounds in the door: five holes, %.0f hp left" % (dmg.health if dmg else -1.0))
	var hp := dmg.health
	var bay: Vector3 = a.global_transform * Vector3(0.0, 0.3, dmg._engine_z)
	a.take_hit(-1, 10.0, -a.global_basis.x, bay + a.global_basis.x * 1.0, Vehicle.HIT_BULLET)
	_check(is_equal_approx(hp - dmg.health, 10.0 * dmg.bullet_scale * dmg.engine_multiplier),
			"a round into the engine bay does %.1fx (%.0f hp)" % [dmg.engine_multiplier, hp - dmg.health])
	for i in 45:
		a.take_hit(-1, 1.0, d[1], d[0] + a.global_basis.z * (0.02 * i - 0.4), Vehicle.HIT_BULLET)
	await _tree.process_frame
	_check(dmg._holes.size() == CarDamage.HOLE_CAP and dmg.holes_made >= 50, "holes are capped at %d, the oldest recycled (%d made)" % [CarDamage.HOLE_CAP, dmg.holes_made])
	# Glass: a round through the side window.
	var glass_at: Vector3 = a.global_transform * Vector3(1.2, dmg._ride + (dmg._top - dmg._ride) * 0.8, -0.3)
	a.take_hit(-1, 10.0, -a.global_basis.x, glass_at, Vehicle.HIT_BULLET)
	var hurt_panes := 0
	for s in dmg.pane_state:
		if s > 0.5:
			hurt_panes += 1
	_check(dmg.pane_state.size() >= 4 and hurt_panes >= 1 and dmg._glass != null,
			"a round through a side window crazes or shatters that pane (%d of %d panes)" % [hurt_panes, dmg.pane_state.size()])
	var lights_before: Mesh = a._night_lights.mesh
	a.take_hit(-1, 10.0, a.global_basis.z, a.global_transform * Vector3(0.62, dmg._ride + (dmg._top - dmg._ride) * 0.42, -dmg._len * 0.5 - 1.0), Vehicle.HIT_BULLET)
	_check(dmg.lamps_broken != 0 and a._night_lights.mesh != lights_before, "a round in a headlamp breaks it and the night glow loses it (bits %d)" % dmg.lamps_broken)
	_check(b._damage == null, "the car next to it is untouched")


func _crash() -> void:
	var c := _car(-4.0)
	await _ticks(40)
	# A wall just ahead of its nose: the crash watch only counts a crash into something.
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(4.0, 2.0, 0.4)
	ws.shape = wb
	wall.add_child(ws)
	_city.add_child(wall)
	_cars.append(wall)
	wall.global_position = c.global_transform * Vector3(0.0, 0.8, -c._dims().length * 0.5 - 0.35)
	await _ticks(2)
	c._crash_v = c.linear_velocity + Vector3(0.0, 0.0, 22.0)
	c._crash_watch()
	_check(c._damage == null, "a 22 m/s stop with nothing behind it (a script setting the velocity) is not a crash")
	c._crash_v = c.linear_velocity + Vector3(0.0, 0.0, -5.0)
	c._crash_watch()
	_check(c._damage == null, "a 5 m/s bump is not a crash")
	c._crash_v = c.linear_velocity + Vector3(0.0, 0.0, -22.0)
	c._crash_watch()
	var dmg: CarDamage = c._damage
	var over := 22.0 - c.crash_min_dv
	_check(dmg != null and dmg._dents.size() == 1 and is_equal_approx(dmg.health, dmg.max_health - over * dmg.crash_damage_per_dv),
			"a 22 m/s crash dents the car and costs %.0f hp" % (dmg.max_health - dmg.health if dmg else -1.0))
	# A landing needs far more.
	c._crash_v = c.linear_velocity + Vector3(0.0, -15.0, 0.0)
	var dents := dmg._dents.size() if dmg else 0
	var hp := dmg.health if dmg else 0.0
	c._crash_watch()
	_check(dmg != null and dmg._dents.size() == dents and is_equal_approx(dmg.health, hp), "a 15 m/s landing is not a crash")


func _rocket_to_wreck() -> void:
	var r := _car(14.0)
	await _ticks(40)
	var blasts := Explosion.blast_count
	# A rocket's blast (radius, damage) thrown gently, so the wreck comes down on the deck: the
	# blast pushes a car once per collision shape, which is several times a rocket's 30 m/s.
	Explosion.blast(r, r.global_position + r.global_basis.x * 1.6 + Vector3.UP * 0.4, 9.0, 8.0, 35.0)
	var dmg: CarDamage = r._damage
	_check(dmg != null and dmg.state == CarDamage.State.BURNING and dmg._fuse <= dmg.quick_fuse.y,
			"a rocket next to a car sets it burning on the short fuse (state %d, %.1f s)" % [dmg.state if dmg else -1, dmg._fuse if dmg else -1.0])
	_check(CarDamage.counts().burning >= 1, "it counts as burning")
	var t := 0
	var before := r.linear_velocity
	while t < 150 and not r.is_wreck():
		before = r.linear_velocity
		await _tree.physics_frame
		t += 1
	_check(r.is_wreck() and Explosion.blast_count == blasts + 2, "it blows up %d ticks later: its own blast, and a wreck (blasts %d)" % [t, Explosion.blast_count - blasts])
	var paint := _paint_of(r)
	_check(r.is_in_group("debris") and is_equal_approx(float(r.get_meta("debris_life", 0.0)), dmg.wreck_lifetime)
			and paint != null and is_equal_approx(float(paint.get_shader_parameter("burnt")), 1.0),
			"the wreck is burnt out and PhysicsBudget frees it after %.0f s" % dmg.wreck_lifetime)
	# The toss happens in the frame it blows up: up TO toss_speed, less whatever it already had,
	# so a wreck still rising from the rocket gains little but leaves at toss_speed or more. Judged
	# by the gain alone, one CI run read +3.0 against a 3.0 floor (build 332).
	var up := r.linear_velocity.y - before.y
	var rising := r.linear_velocity.y
	await _ticks(40)
	var finite := r.global_position.is_finite() and r.linear_velocity.is_finite() and r.global_basis.x.is_finite()
	_check(finite and (up > 3.0 or rising > dmg.toss_speed.x - 0.5),
			"the blast throws the wreck up (+%.1f m/s, rising at %.1f m/s) and it stays finite" % [up, rising])
	# Still for 20 ticks running, not slow for one: the top of a bounce is slow too, and a wreck
	# caught there read 2.79 m over the deck in a full suite run.
	var landed := 0
	var still := 0
	while landed < 480 and still < 20:
		await _tree.physics_frame
		landed += 1
		if r.linear_velocity.length() < 0.5 and r.global_position.y < _top.y + 3.0:
			still += 1
		else:
			still = 0
	var over := r.global_position.y - _top.y
	# On its rims, its side or its roof (the toss spins it).
	_check(r.global_position.is_finite() and over > -0.2 and over < 2.6 and r.linear_velocity.length() < 1.0,
			"the wreck comes down and rests on the deck (%.2f m over it, %d ticks)" % [over, landed])
	var hp_before := dmg.health
	r.take_hit(-1, 10.0, Vector3.DOWN, r.global_position + Vector3.UP, Vehicle.HIT_BULLET)
	_check(dmg.health == hp_before and r.is_wreck(), "a wreck takes no more damage")


## The fire's stages: the engine bay (flames, licks, embers, the black smoke replacing the grey
## wisps), the cabin (flames out of the frames, the side glass popped, the glow inside), and the
## wreck's fire burning out (every flame system, the light and the burning count gone).
func _fire_stages() -> void:
	var c := _car(-44.0)
	await _ticks(20)
	c.take_hit(-1, 900.0, Vector3.DOWN, c.global_position + Vector3.UP)
	var d: CarDamage = c._damage
	d._fuse = 1e6
	_check(d._flames != null and d._licks != null and d._embers != null and d._cabin_fire == null
			and d._smoke != null and d._smoke.name == "FireSmoke",
			"a car on fire burns in the engine bay: flames, licks, embers, black smoke")
	d._spread_to_cabin(1.0)
	var popped := 0
	var tempered := 0
	for i in d._panes.size():
		if int(d._panes[i][3]) == 0:
			tempered += 1
			if d.pane_state[i] >= 2.0:
				popped += 1
	var glow := float(d._glass.get_shader_parameter("cabin_fire")) if d._glass else 0.0
	_check(d._cabin_fire != null and d._cabin_fire.emission_points.size() > 4 and popped == tempered and glow > 0.9,
			"the fire takes the cabin: %d flame points out of the frames, %d of %d panes popped, the cabin glows" % [
			d._cabin_fire.emission_points.size() if d._cabin_fire else 0, popped, tempered])
	var burning: int = CarDamage.counts().burning
	d.become_wreck()
	d._wreck_t = d.wreck_fire_seconds + 0.1
	for i in 3:
		await _tree.process_frame
	_check(d._flames == null and d._cabin_fire == null and d._fire_light == null and int(CarDamage.counts().burning) == burning - 1,
			"the wreck's fire burns out: every flame system and the light gone, one fewer burning")


func _blame_and_caps() -> void:
	var p := _car(26.0)
	await _ticks(20)
	var d := _door(p)
	Police.innocent = true
	p.take_hit(-1, 8.0, d[1], d[0], Vehicle.HIT_BULLET)
	Police.innocent = false
	_check(p._damage != null and p._damage.blame_police, "a police round in a car is the police's doing")
	p.take_hit(-1, 8.0, d[1], d[0], Vehicle.HIT_BULLET)
	_check(not p._damage.blame_police, "the player's next round makes it the player's again")
	# Burning cap: one fire allowed, the second car stays smoking just short of it.
	CarDamage.max_burning = CarDamage.counts().burning + 1
	var f1 := _car(32.0)
	var f2 := _car(38.0)
	await _ticks(10)
	f1.take_hit(-1, 900.0, Vector3.DOWN, f1.global_position + Vector3.UP)
	f2.take_hit(-1, 900.0, Vector3.DOWN, f2.global_position + Vector3.UP)
	_check(f1._damage.state == CarDamage.State.BURNING and f2._damage.state == CarDamage.State.SMOKING,
			"the burning cap holds: the next car smokes instead (%d, %d)" % [f1._damage.state, f2._damage.state])
	f1._damage._fuse = 1e6
	# Wreck cap: three wrecks with room for two.
	CarDamage.max_wrecks = 2
	var ws: Array = []
	for i in 3:
		ws.append(_car(44.0 + i * 5.0))
	await _ticks(10)
	for w in ws:
		w.damage_state().become_wreck()
	await _tree.process_frame
	var oldest_gone: bool = not is_instance_valid(ws[0]) or (ws[0] as Node).is_queued_for_deletion()
	_check(CarDamage.counts().wrecks <= 2 and oldest_gone,
			"the wreck cap holds (%d kept), the oldest goes" % CarDamage.counts().wrecks)


func _driven_car(player: Player) -> void:
	var car := _car(0.0, 0)
	await _ticks(30)
	player.global_position = car.global_position + car.global_basis.x * 2.5
	player.enter_vehicle(car)
	await _ticks(2)
	var hp: float = player.health.health
	car.damage_state().explode()
	await _ticks(3)
	_check(not player.is_driving() and car.is_wreck(), "the driven car throws the player out when it goes up")
	_check(player.health.health >= hp, "the player takes no blast damage (self_blast_damage off)")
	player.global_position = car.global_position + car.global_basis.x * 2.5
	player.velocity = Vector3.ZERO
	await _ticks(2)
	player._try_enter_vehicle()
	_check(player.vehicle != car, "a wreck cannot be driven")
	if player.is_driving():
		player.exit_vehicle()
	player.global_position = _top + Vector3(0.0, 1.2, 34.0)
	player.velocity = Vector3.ZERO


func _pooled_cruiser() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cop := PoliceCar.make(false, rng)
	_city.add_child(cop)
	cop.global_position = _top + Vector3(-30.0, 0.9, 12.0)
	_cars.append(cop)
	await _ticks(5)
	var plain := _paint_of(cop)
	var d := _door(cop)
	cop.take_hit(-1, 10.0, d[1], d[0], Vehicle.HIT_BULLET)
	var hurt := cop._damage != null and _paint_of(cop) != plain and not cop.is_traffic()
	cop.strip_for_pool()
	await _tree.process_frame
	_check(hurt and cop._damage == null and _paint_of(cop) == plain, "a cruiser shot up and pooled comes back clean")


## Every car in the city nobody has hit still has no damage and wears the plain paint.
func _city_cars_clean() -> void:
	var plain := 0
	var hit := 0
	var bad := 0
	for n in _tree.get_nodes_in_group("vehicle"):
		var car := n as Vehicle
		if car == null or _cars.has(car) or car is Aircraft:
			continue
		if car._damage != null:
			hit += 1
			continue
		var m := _paint_of(car)
		if m == null or m.shader == Vehicle.PAINT_SHADER:
			plain += 1
		else:
			bad += 1
	_check(bad == 0 and plain > 0, "every undamaged car in the city keeps the shared paint shader (%d plain, %d hit earlier)" % [plain, hit])
