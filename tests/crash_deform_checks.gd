extends RefCounted
## Crash deformation checks for tests/smoke_test.gd (scripts/vehicles/crash_deform.gd,
## crash_litter.gd, shaders/car_crumple.gdshaderinc). Loaded at run time, so it can name Vehicle,
## CarDamage and CrashDeform. Like car_damage_checks.gd it works on a deck of its own high over
## the street with the player standing on it, and frees everything it made.
## Checks: the shaders compile with the crumple uniforms; an undamaged car and a shot car have no
## crumple; a gentle crash scrapes but does not crumple; a head-on crumples the nose by about the
## crush its speed asks for, deeper the faster it went, and a second hit there deepens it; the
## bonnet springs and a hard one hangs the bumper; the trim, chrome, glass and lamps move onto
## materials that carry the crush; the crushed nose moves back and the tail does not; a side hit
## by a wheel knocks it out of line and restore() puts it back; a roof landing crushes down; a
## slide scrapes; broken lamps and panes leave shards on the deck; a real 60 km/h run into a wall
## crumples through the crash watch; CRASH_DEFORM off (the A/B) leaves only the old dents.

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
	var was_enabled := CrashDeform.enabled
	CrashDeform.enabled = true
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 260.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 40.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_shaders()
	await _no_crumple_yet()
	await _speeds()
	await _panels_and_parts()
	await _wheels()
	await _roll_and_scrape()
	await _shards()
	await _real_crash()
	await _switch_off()

	CrashDeform.enabled = was_enabled
	var litter := CrashLitter.instance()
	if litter != null:
		litter.clear()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, "crash deform: " + label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 140.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(x: float, z: float = 0.0, type: int = 0) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.55, 0.12, 0.1), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(x, 0.9, z)
	_made.append(car)
	return car


## A wall just off the car's body-space point `at` (a crash only counts into something).
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


## A head-on at `kmh` through the crash watch (the velocity change set by hand: the same path a
## real crash takes, with an exact number), into a wall at the nose.
func _head_on(car: Vehicle, kmh: float) -> void:
	car._crash_v = car.linear_velocity + car.global_basis.z * -(kmh / 3.6)
	car._crash_hold = 0
	car._crash_watch()


func _shaders() -> void:
	for p in ["res://shaders/car_paint_damage.gdshader", "res://shaders/car_glass_damage.gdshader",
			"res://shaders/car_lamp_damage.gdshader", "res://shaders/car_part_damage.gdshader",
			"res://shaders/car_detail_damage.gdshader"]:
		var sh: Shader = load(p)
		var names := []
		for u: Dictionary in sh.get_shader_uniform_list():
			names.append(u.name)
		_check(names.has("crumple_count") and names.has("panel_count"), "%s carries the crumple uniforms" % p.get_file())
	var paint: Shader = load("res://shaders/car_paint_damage.gdshader")
	var has_scrape := false
	for u: Dictionary in paint.get_shader_uniform_list():
		has_scrape = has_scrape or u.name == "scrape_count"
	_check(has_scrape, "the damaged paint carries the scrapes")
	var plain: Shader = load("res://shaders/car_paint.gdshader")
	var leaked := false
	for u: Dictionary in plain.get_shader_uniform_list():
		leaked = leaked or u.name == "crumple_count"
	_check(not leaked, "an undamaged car's paint shader has none of it (cost unchanged)")


func _no_crumple_yet() -> void:
	var a := _car(-40.0)
	await _ticks(30)
	_check(a._damage == null, "an undamaged car has no damage at all")
	a.take_hit(-1, 10.0, -a.global_basis.x, a.global_transform * Vector3(0.95, 0.45, 0.3), Vehicle.HIT_BULLET)
	_check(a._damage != null and a._damage._crumple == null, "a round makes damage but no crumple")
	# A gentle knock (just past the dent threshold, under the crumple one) dents and scrapes only.
	_wall_at(a, Vector3(0.0, 0.0, -float(a._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
	await _ticks(2)
	_head_on(a, (a.crash_min_dv + 1.0) * 3.6)
	var cd: CrashDeform = a._damage._crumple
	_check(a._damage._dents.size() >= 1 and (cd == null or cd._zones.is_empty()),
			"a crash 1 m/s past the threshold dents but does not crumple")


## Depth for speed: 30 km/h is nothing, 50 / 70 / 90 crush ever deeper, within the caps.
func _speeds() -> void:
	var depths := []
	var x := -28.0
	for kmh in [30.0, 50.0, 70.0, 90.0]:
		var c := _car(x)
		x += 7.0
		await _ticks(30)
		_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
		await _ticks(2)
		_head_on(c, kmh)
		var cd: CrashDeform = c._damage._crumple if c._damage != null else null
		depths.append(cd.crush_at_end(-1.0) if cd != null else 0.0)
	_check(depths[0] == 0.0, "a 30 km/h crash crumples nothing (%.2f m)" % depths[0])
	_check(depths[1] > 0.05 and depths[2] > depths[1] and depths[3] > depths[2],
			"faster is deeper: %s m at 50 / 70 / 90 km/h" % str(depths))
	var cd70: CrashDeform = (_made[_made.size() - 4] as Vehicle)._damage._crumple
	var want: float = cd70.depth_per_dv * (70.0 / 3.6 - 8.0 - cd70.min_over * 0.5)
	_check(absf(float(depths[2]) - want) < 0.03, "70 km/h crushes the nose %.2f m (wants %.2f)" % [depths[2], want])
	_check(float(depths[3]) <= cd70.max_hit_depth + 1e-4, "one hit stays under max_hit_depth")


func _panels_and_parts() -> void:
	var c := _car(4.0)
	await _ticks(30)
	_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
	await _ticks(2)
	_head_on(c, 75.0)
	var dmg := c._damage
	var cd := dmg._crumple
	_check(cd != null and cd._zones.size() == 1, "a 75 km/h head-on makes one crumple zone")
	if cd == null:
		return
	var first := cd.crush_at_end(-1.0)
	_check(cd._panel_angle[CrashDeform.Lid.BONNET] > 0.0, "the bonnet springs (%.3f rad)" % cd._panel_angle[CrashDeform.Lid.BONNET])
	_check(cd._panel_angle[CrashDeform.Lid.BUMPER_FRONT] != 0.0 and cd._panel_angle[CrashDeform.Lid.BUMPER_REAR] == 0.0,
			"the front bumper hangs off a corner, the rear one does not")
	# A second hit on the same nose goes deeper, still one zone, never past max_crush.
	c._crash_hold = 0
	_head_on(c, 60.0)
	_check(cd._zones.size() == 1 and cd.crush_at_end(-1.0) > first and cd.crush_at_end(-1.0) <= cd.max_crush + 1e-4,
			"a second hit deepens the same zone (%.2f -> %.2f m)" % [first, cd.crush_at_end(-1.0)])
	await _tree.process_frame
	var paint := dmg._paint
	_check(paint != null and int(paint.get_shader_parameter("crumple_count")) == 1 and int(paint.get_shader_parameter("panel_count")) >= 2,
			"the paint carries the crumple and the panels")
	var all_ok := true
	for m in cd._materials():
		all_ok = all_ok and int((m as ShaderMaterial).get_shader_parameter("crumple_count")) == 1
	_check(all_ok and cd._materials().size() >= 2, "every body material carries the same crumple (%d)" % cd._materials().size())
	# The trim / chrome of the near body move onto the part shader (where the model has those slots).
	var slots := 0
	var swapped := 0
	if dmg._mesh != null and dmg._mesh.mesh != null:
		for si in dmg._mesh.mesh.get_surface_count():
			var src := dmg._mesh.mesh.surface_get_material(si) as StandardMaterial3D
			if src != null and String(src.resource_name) in ["trim", "chrome"]:
				slots += 1
				var om := dmg._mesh.get_surface_override_material(si) as ShaderMaterial
				if om != null and om.shader == CrashDeform.PART_SHADER:
					swapped += 1
	_check(swapped == slots, "the trim and chrome ride the crush (%d of %d)" % [swapped, slots])
	# The crushed nose moves back, the tail does not.
	var nose := dmg._to_mesh * Vector3(0.0, (dmg._ride + dmg._top) * 0.4, -dmg._len * 0.5)
	var tail := dmg._to_mesh * Vector3(0.0, (dmg._ride + dmg._top) * 0.4, dmg._len * 0.5)
	var back := (dmg._to_mesh.affine_inverse() * cd.move_point(nose, Vector3.FORWARD) - dmg._to_mesh.affine_inverse() * nose).z
	var still := (cd.move_point(tail, Vector3.BACK) - tail).length()
	_check(back > cd.crush_at_end(-1.0) * 0.6 and still < 1e-4, "the nose goes back %.2f m, the tail stays (%.4f)" % [back, still])


func _wheels() -> void:
	var c := _car(12.0)
	await _ticks(30)
	var hw := float(c._dims().width) * 0.5
	var fl: Node3D = null
	for rig: Array in c._wheel_rigs:
		var n := rig[0] as Node3D
		if n.position.x > 0.0 and n.position.z < 0.0:
			fl = n
	_wall_at(c, Vector3(hw + 0.35, 0.0, fl.position.z if fl else -1.3), Vector3(0.4, 2.0, 1.2))
	await _ticks(2)
	var before := fl.rotation if fl else Vector3.ZERO
	c._crash_v = c.linear_velocity + c.global_basis.x * (50.0 / 3.6)
	c._crash_hold = 0
	c._crash_watch()
	var cd: CrashDeform = c._damage._crumple if c._damage != null else null
	_check(cd != null and fl != null and absf(fl.rotation.z - before.z) > 0.03,
			"a side hit at the front wheel knocks it out of line (camber %.3f rad)" % (fl.rotation.z if fl else 0.0))
	if cd != null and fl != null:
		cd.reset()
		_check(fl.rotation.is_equal_approx(before), "restore() puts the wheel back")


func _roll_and_scrape() -> void:
	var c := _car(20.0)
	await _ticks(30)
	c.damage_state().stage("roll,scrape")
	var cd: CrashDeform = c._damage._crumple
	var down := false
	if cd != null:
		for z: Array in cd._zones:
			down = down or (z[1] as Vector3).y < -0.8
	_check(down, "landing on the roof crushes it down")
	await _tree.process_frame
	_check(cd != null and cd._scrapes.size() >= 1 and int(c._damage._paint.get_shader_parameter("scrape_count")) >= 1,
			"a slide along a wall scrapes the paint")
	_check(c._damage._glass == null or int(c._damage._glass.get_shader_parameter("crumple_count")) >= 1,
			"the glass rides the caved roof")


func _shards() -> void:
	var c := _car(28.0)
	await _ticks(30)
	var litter := CrashLitter.instance()
	var before := litter.laid if litter != null else 0
	c.damage_state()._break_lamps(CarDamage.LAMP_HEAD_L | CarDamage.LAMP_TAIL_R)
	litter = CrashLitter.instance()
	_check(litter != null and litter.laid > before, "broken lamps leave lens shards on the road (%d)" % ((litter.laid - before) if litter else 0))
	if litter == null:
		return
	var mm: MultiMesh = (litter.get_child(0) as MultiMeshInstance3D).multimesh
	_check(mm.visible_instance_count == mini(litter.laid, mm.instance_count) and litter.get_parent() is Node3D,
			"one MultiMesh for every shard, under the level root (rides the origin shifts)")
	var many := litter.laid
	for i in 40:
		CrashLitter.scatter(c, c.global_position, Vector3.ZERO, CrashLitter.Kind.GLASS, 40)
	_check(mm.visible_instance_count == mm.instance_count and litter.laid > many, "the ring is capped at %d shards" % mm.instance_count)


## A real crash: the car run into a wall at 60 km/h, the crash watch and the physics doing it.
func _real_crash() -> void:
	var c := _car(-20.0, -30.0)
	await _ticks(40)
	_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 6.0), Vector3(6.0, 3.0, 1.0))
	await _ticks(2)
	c.sleeping = false
	c.linear_velocity = -c.global_basis.z * (60.0 / 3.6)
	c.hold_crash_watch(2)
	var t := 0
	while t < 120 and (c._damage == null or c._damage._crumple == null):
		await _tree.physics_frame
		t += 1
	var cd: CrashDeform = c._damage._crumple if c._damage != null else null
	_check(cd != null and cd.crush_at_end(-1.0) > 0.05,
			"a real 60 km/h run into a wall crumples the nose (%.2f m, %d ticks)" % [cd.crush_at_end(-1.0) if cd else 0.0, t])
	var nan := false
	for v in [c.global_position, c.linear_velocity]:
		nan = nan or is_nan(v.x) or is_nan(v.y) or is_nan(v.z)
	_check(not nan, "no NaN after the crash")


func _switch_off() -> void:
	CrashDeform.enabled = false
	var c := _car(36.0)
	await _ticks(30)
	_wall_at(c, Vector3(0.0, 0.0, -float(c._dims().length) * 0.5 - 0.35), Vector3(4.0, 2.0, 0.4))
	await _ticks(2)
	_head_on(c, 80.0)
	_check(c._damage != null and c._damage._crumple == null and c._damage._dents.size() >= 1,
			"CRASH_DEFORM off: the old dent and no crumple")
	CrashDeform.enabled = true
