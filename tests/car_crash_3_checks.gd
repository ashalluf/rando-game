extends RefCounted
## Crash breakup checks for tests/smoke_test.gd (scripts/vehicles/crash_breakup.gd,
## crash_debris.gd, shaders/car_paint_open.gdshader, the airbag in car_cabin.gdshaderinc). Loaded
## at run time, so it can name Vehicle, CarDamage, CrashDeform and CrashBreakup. Like
## crash_deform_checks.gd it works on a deck of its own high over the street with the player
## standing on it, and frees everything it made.
## Checks: the shaders carry what they need; a shot car has no breakup; a hard head-on throws the
## bonnet open (paint drawn from both sides, an engine bay under it), fires the airbags (the glass's
## uniform) and knocks off debris that lands and stays; a T-bone bursts the glass facing it and
## TRIPS the car over (a real roll by the physics, flight held off meanwhile, the centre of mass put
## back once it rests); a very hard corner hit tears the wheel off and it rolls away as a body;
## what drags throws sparks while the car moves; restore() puts it all back; CRASH_BREAKUP off
## (the A/B) makes none of it.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _ws: Node
var _deck: StaticBody3D
var _made: Array = []
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
	var deform_was := CrashDeform.enabled
	var was := CrashBreakup.enabled
	CrashDeform.enabled = true
	CrashBreakup.enabled = true
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_shaders()
	await _shot_car()
	await _head_on()
	await _tbone_rolls()
	await _wheel_off()
	await _drag_sparks()
	await _switch_off()

	CrashBreakup.enabled = was
	CrashDeform.enabled = deform_was
	var debris := CrashDebris.instance()
	if debris != null:
		debris.clear()
	var litter := CrashLitter.instance()
	if litter != null:
		litter.clear()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()
	for b in _tree.get_nodes_in_group("debris"):
		if b.name.begins_with("TornWheel"):
			b.queue_free()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, "car crash 3: " + label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180.0, 1.0, 180.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(x: float, z: float = 0.0, type: int = 0) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.2, 0.3, 0.55), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(x, 0.9, z)
	_made.append(car)
	return car


func _wall_at(car: Vehicle, at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = size
	ws.shape = wb
	wall.add_child(ws)
	_city.add_child(wall)
	_made.append(wall)
	wall.global_position = car.global_transform * at
	wall.global_basis = car.global_basis
	return wall


## A crash through the crash watch: the velocity change `body_dv` (body space, m/s) set by hand.
func _crash(car: Vehicle, body_dv: Vector3) -> void:
	car._crash_v = car.linear_velocity - car.global_basis * body_dv
	car._crash_hold = 0
	car._crash_watch()


func _shaders() -> void:
	var open: Shader = load("res://shaders/car_paint_open.gdshader")
	var names := []
	for u: Dictionary in open.get_shader_uniform_list():
		names.append(u.name)
	_check(names.has("panel_count") and names.has("crumple_count") and names.has("hole_count"),
			"the two-sided paint is the damage paint (%d uniforms)" % names.size())
	var glass: Shader = load("res://shaders/car_glass_damage.gdshader")
	var has_bag := false
	for u: Dictionary in glass.get_shader_uniform_list():
		has_bag = has_bag or u.name == "airbag"
	_check(has_bag, "the damaged glass's cabin carries the airbags")
	var plain: Shader = load("res://shaders/car_glass.gdshader")
	var leaked := false
	for u: Dictionary in plain.get_shader_uniform_list():
		leaked = leaked or u.name == "airbag"
	_check(not leaked, "an undamaged car's glass has none of it (cost unchanged)")
	var s := CrashBreakup.airbag_shape(0.02)
	var full := CrashBreakup.airbag_shape(0.2)
	var limp := CrashBreakup.airbag_shape(3.0)
	_check(s.x > 0.4 and full.x > 0.99 and limp.x < 0.5 and limp.y > 0.99 and CrashBreakup.airbag_shape(-1.0) == Vector2.ZERO,
			"an airbag fills in 30 ms and hangs limp once vented (%s %s %s)" % [s, full, limp])


func _shot_car() -> void:
	var c := _car(-60.0)
	await _ticks(20)
	c.take_hit(-1, 10.0, -c.global_basis.x, c.global_transform * Vector3(0.95, 0.45, 0.3), Vehicle.HIT_BULLET)
	_check(c._damage != null and c._damage._breakup == null, "a round breaks nothing off")


func _head_on() -> void:
	var c := _car(-45.0)
	await _ticks(30)
	_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
	await _ticks(2)
	var debris_before := CrashDebris.instance().thrown if CrashDebris.instance() != null else 0
	_crash(c, Vector3(0.0, 0.0, 75.0 / 3.6))
	var bk: CrashBreakup = c._damage._breakup if c._damage != null else null
	_check(bk != null, "a 75 km/h head-on breaks things off")
	if bk == null:
		return
	_check(bk.bonnet_angle > 0.0 and c._damage._paint != null and c._damage._paint.shader == CrashBreakup.OPEN_PAINT,
			"the bonnet's catch lets go and the paint is drawn from both sides")
	_check(bk.airbag_t >= 0.0, "the front airbags fire")
	await _ticks(20)
	_check(bk.bonnet_angle > 0.3, "the bonnet flies up (%.2f rad)" % bk.bonnet_angle)
	var bay := c.get_node_or_null("EngineBay") as MeshInstance3D
	_check(bay != null and bay.visible, "an engine bay shows under it")
	var bag: Vector2 = c._damage._glass.get_shader_parameter("airbag") if c._damage._glass != null else Vector2.ZERO
	_check(bag.x > 0.5, "the glass draws the bags full (%s)" % bag)
	var debris := CrashDebris.instance()
	_check(debris != null and debris.thrown > debris_before, "pieces are knocked off (%d)" % ((debris.thrown - debris_before) if debris else 0))
	await _ticks(240)
	_check(debris != null and debris.resting > 0 and debris._flying.is_empty(), "they land and lie still (%d)" % (debris.resting if debris else 0))
	var mm: MultiMesh = (debris.get_child(0) as MultiMeshInstance3D).multimesh
	_check(mm.visible_instance_count >= debris.resting and debris.get_parent() is Node3D, "and stay drawn, one MultiMesh under the level root")
	var bag2: Vector2 = c._damage._glass.get_shader_parameter("airbag") if c._damage._glass != null else Vector2.ZERO
	_check(bag2.y > 0.9 and bag2.x < bag.x, "the bags vent and hang limp (%s)" % bag2)
	# restore() (a pooled cruiser) puts it back.
	c._damage.restore()
	_check(bk.bonnet_angle < 0.0 and (bay == null or bay.is_queued_for_deletion()), "restore() shuts it again")


## A T-bone: the glass facing it bursts and the car goes over.
func _tbone_rolls() -> void:
	var c := _car(-20.0)
	await _ticks(40)
	var hw := float(c._dims().width) * 0.5
	_wall_at(c, Vector3(hw + 0.4, 0.0, 0.0), Vector3(0.4, 2.0, 3.0))
	await _ticks(2)
	_crash(c, Vector3(-80.0 / 3.6, 0.0, 0.0))
	var bk: CrashBreakup = c._damage._breakup if c._damage != null else null
	_check(bk != null and bk.bursts > 0, "a T-bone bursts the glass facing it (%d panes)" % (bk.bursts if bk else 0))
	if bk == null:
		return
	_check(bk.rolls == 1 and bk.tumble_left > 0.0 and c.tumble_until > Time.get_ticks_msec() / 1000.0,
			"the car is tripped (flight stabilisation held off)")
	var road := float(c._dims().get("road", -0.2))
	_check(absf(c.center_of_mass.y - (road + bk.roll_com_height)) < 0.01, "the centre of mass up at a real car's (%.2f)" % c.center_of_mass.y)
	var lowest := 1.0
	var t := 0
	while t < 360:
		await _tree.physics_frame
		t += 1
		lowest = minf(lowest, c.global_basis.y.y)
		if bk.tumble_left <= 0.0 and t > 60:
			break
	_check(lowest < 0.25, "it rolls over by the physics (up axis down to %.2f)" % lowest)
	var nan := false
	for v in [c.global_position, c.linear_velocity, c.angular_velocity]:
		nan = nan or is_nan(v.x) or is_nan(v.y) or is_nan(v.z)
	_check(not nan, "no NaN in the roll")
	while t < 900 and bk.tumble_left > 0.0:
		await _tree.physics_frame
		t += 1
	_check(bk.tumble_left <= 0.0 and c.tumble_until <= 0.0 and absf(c.center_of_mass.y - c.center_of_mass_height) < 0.01,
			"once it rests the handling's centre of mass is back (%.1f s)" % (t / 60.0))


func _wheel_off() -> void:
	var c := _car(10.0)
	await _ticks(30)
	var fr := -1
	for i in c._wheel_rigs.size():
		var n := c._wheel_rigs[i][0] as Node3D
		if n.position.x > 0.0 and n.position.z < 0.0:
			fr = i
	var node := c._wheel_rigs[fr][0] as Node3D
	var hw := float(c._dims().width) * 0.5
	_wall_at(c, Vector3(hw * 0.6, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(1.2, 2.0, 0.4))
	await _ticks(2)
	var wheels_before := 0
	for b in _tree.get_nodes_in_group("debris"):
		wheels_before += 1 if b.name.begins_with("TornWheel") else 0
	# A 100 km/h offset hit on the right of the nose.
	c.damage_state().breakup()
	c._damage.breakup().crash(Vector3(node.position.x, 0.4, node.position.z - 0.7), Vector3(-0.25, 0.0, 1.0).normalized(),
			100.0 / 3.6 - c.crash_min_dv, c.global_transform * Vector3(node.position.x, 0.4, node.position.z - 0.7))
	var bk: CrashBreakup = c._damage._breakup
	_check(bk.torn.has(fr) and not node.visible, "a 100 km/h hit at the corner tears that wheel off")
	var torn := 0
	var body: RigidBody3D = null
	for b in _tree.get_nodes_in_group("debris"):
		if b.name.begins_with("TornWheel"):
			torn += 1
			body = b as RigidBody3D
	_check(torn == wheels_before + 1 and body != null and body.get_meta("debris_life", 0.0) >= 100.0,
			"it is a body of its own that stays (PhysicsBudget debris)")
	var vw := bk._physics_wheel(node.position)
	_check(vw != null and vw.wheel_radius < 0.15, "the corner is down on its hub (%.2f m)" % (vw.wheel_radius if vw else 0.0))
	if body != null:
		var start := body.global_position
		await _ticks(60)
		_check(body.global_position.distance_to(start) > 1.0, "the wheel rolls away (%.1f m)" % body.global_position.distance_to(start))
	c._damage.restore()
	_check(node.visible and bk.torn.is_empty() and (vw == null or vw.wheel_radius > 0.2), "restore() puts the wheel back")


func _drag_sparks() -> void:
	var c := _car(25.0)
	await _ticks(30)
	c.damage_state().stage("front75")
	var bk := c._damage.breakup()
	var cd := c._damage._crumple
	_check(cd != null and float(cd._panel_angle[CrashDeform.Lid.BUMPER_FRONT]) != 0.0, "the bumper hangs off a corner")
	bk.stage_speed = 14.0
	bk.set_physics_process(true)
	await _ticks(12)
	var on := false
	for p in bk._sparks:
		on = on or p.emitting
	_check(on, "the hanging bumper throws sparks where it drags")
	bk.stage_speed = 0.0
	await _ticks(12)
	on = false
	for p in bk._sparks:
		on = on or p.emitting
	_check(not on, "and none once the car stands still")


func _switch_off() -> void:
	CrashBreakup.enabled = false
	var c := _car(40.0)
	await _ticks(30)
	_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
	await _ticks(2)
	_crash(c, Vector3(0.0, 0.0, 90.0 / 3.6))
	_check(c._damage != null and c._damage._crumple != null and c._damage._breakup == null,
			"CRASH_BREAKUP off: the crumple and nothing broken off")
	CrashBreakup.enabled = true
