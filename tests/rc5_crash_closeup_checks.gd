extends RefCounted
## The crash_closeup refcam's checks for tests/smoke_test.gd (scripts/vehicles/crash_aftermath.gd,
## the pole wrap in crash_deform.gd / car_crumple.gdshaderinc, the popped bonnet in
## crash_breakup.gd, shaders/crash_fluids.gdshader, tools/refcams/crash_stage.gd). Loaded at run
## time, so it can name Vehicle, CarDamage, CrashDeform, CrashBreakup and CrashAftermath. Works on
## a deck of its own high over the street (car_crash_3_checks.gd's way) and frees what it made.
## Checks: the shader and the camera row; a pole noted for a frame is used once and expires; a
## pole hit makes a narrow V zone deeper than a wall's at the same speed and hangs no bumper; a
## 55 km/h hit pops the bonnet a few degrees where a 75 km/h one still throws it wide (the old
## head-on check holds that); a front crush leaks a pool under the nose that spreads and steams;
## CRASH_AFTERMATH off (the A/B) makes the old wide crush, no pool and no steam.

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
	var breakup_was := CrashBreakup.enabled
	var was := CrashAftermath.enabled
	CrashDeform.enabled = true
	CrashBreakup.enabled = true
	CrashAftermath.enabled = true
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 340.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 70.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_static()
	await _note_expires()
	await _pole_wrap()
	await _switch_off()

	CrashAftermath.enabled = was
	CrashBreakup.enabled = breakup_was
	CrashDeform.enabled = deform_was
	var fl := CrashAftermath.instance()
	if fl != null:
		fl.clear()
	for k in [CrashDebris.instance(), CrashLitter.instance()]:
		if k != null:
			k.clear()
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
	_t._check(ok, "crash closeup: " + label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0, 1.0, 160.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(x: float) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.15, 0.25, 0.5), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(x, 0.9, 0.0)
	_made.append(car)
	return car


func _static() -> void:
	var sh: Shader = load("res://shaders/crash_fluids.gdshader")
	var names := []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(u.name)
	_check(names.has("spread") and names.has("flow") and names.has("coolant"), "the fluid shader's uniforms (%s)" % str(names))
	var src := FileAccess.get_file_as_string("res://shaders/crash_fluids.gdshader")
	_check(src.contains("color_space.gdshaderinc") and src.contains("cs_out("), "the fluids are linear on both renderers")
	var inc := FileAccess.get_file_as_string("res://shaders/car_crumple.gdshaderinc")
	_check(inc.count("crumple_shape[i].w > 0.5") >= 2 and inc.count("step(0.5, crumple_shape[i].w)") >= 2,
			"the crumple shader knows a pole's zone in both cr_move and cr_stress")
	_check(FileAccess.get_file_as_string("res://scripts/world/prop_break.gd").contains("CrashAftermath.note_pole("),
			"a car smashing through a pole notes it")
	var cams: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if cams is Dictionary:
		for c: Dictionary in cams.get("cameras", []):
			if c.get("name", "") == "crash_closeup":
				row = c
	_check(row.get("stage", "") == "crash" and row.get("crash") is Dictionary and float(row.get("hour", 0.0)) == 13.0,
			"the crash_closeup camera row stages a crash at 13:00")
	_check(FileAccess.file_exists("res://tools/refcams/crash_stage.gd")
			and FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd").contains("crash_stage.gd"), "and refcams_shot runs its stager")
	_check(CrashAftermath.bonnet_rest(7.0, 11.0, 0.8, 0.5) < 0.15 and is_equal_approx(CrashAftermath.bonnet_rest(13.0, 11.0, 0.8, 0.5), 0.8),
			"a bonnet pops below the fly-off speed and flies past it")


func _note_expires() -> void:
	CrashAftermath.note_pole(0.3)
	_check(CrashAftermath.take_pole() > 0.0 and CrashAftermath.take_pole() == 0.0, "a noted pole is used once")
	CrashAftermath.note_pole(0.3)
	await _ticks(1)
	_check(CrashAftermath.take_pole() == 0.0, "and only in the frame it was noted")


func _pole_wrap() -> void:
	var wall := _car(-40.0)
	var pole := _car(-25.0)
	await _ticks(30)
	var pools_before := CrashAftermath.instance().pools_made if CrashAftermath.instance() != null else 0
	wall.damage_state().stage("front55")
	pole.damage_state().stage("pole55")
	await _ticks(2)
	var cw := wall._damage._crumple
	var cp := pole._damage._crumple
	_check(cw != null and cp != null, "both cars crumple")
	if cw == null or cp == null:
		return
	var zw: Array = cw._zones[0]
	var zp: Array = cp._zones[0]
	_check(cp._crumple_shape[0].w > 0.5 and cw._crumple_shape[0].w < 0.5, "the pole's zone is marked a pole's, the wall's is not")
	_check(cp._crumples[0].w < cw._crumples[0].w * 0.9, "the pole's zone is narrower (%.2f vs %.2f mesh units)" % [cp._crumples[0].w, cw._crumples[0].w])
	_check(float(zp[2]) > float(zw[2]) * 1.15, "and deeper (%.2f m vs %.2f m)" % [float(zp[2]), float(zw[2])])
	_check(cp._panel_angle[CrashDeform.Lid.BUMPER_FRONT] == 0.0, "a pole wraps the bumper: none hangs")
	# The V: a point at the pole is pushed back further than one at the far corner.
	var ms := pole._damage._mesh_scale
	var at := pole._damage._to_mesh * Vector3(0.25, 0.4, -pole._damage._len * 0.5)
	var corner := pole._damage._to_mesh * Vector3(-pole._damage._width * 0.45, 0.4, -pole._damage._len * 0.5)
	var push_at := (cp.move_point(at, Vector3.FORWARD) - at).length() * ms
	var push_corner := (cp.move_point(corner, Vector3.FORWARD) - corner).length() * ms
	_check(push_at > 0.3 and push_corner < push_at * 0.4, "the nose bends into a V round it (%.2f m at the pole, %.2f m at the far corner)" % [push_at, push_corner])
	await _ticks(90)
	var bk := pole._damage._breakup
	_check(bk != null and bk.bonnet_angle >= 0.0 and bk.bonnet_angle < 0.2, "at 55 km/h the bonnet pops off its catch, it does not fly open (%.2f rad)" % (bk.bonnet_angle if bk else -1.0))
	_check(bk != null and bk.airbag_t >= 0.0, "the airbags fired")
	var fl := CrashAftermath.instance()
	_check(fl != null and fl.pools_made >= pools_before + 2, "both front crushes leak (%d pools)" % ((fl.pools_made - pools_before) if fl else 0))
	if fl == null:
		return
	var nose := pole.global_transform * Vector3(0.0, 0.0, -pole._damage._len * 0.5)
	var near := false
	var spread := 0.0
	for e: Array in fl._pools:
		var mi := e[0] as MeshInstance3D
		if is_instance_valid(mi) and mi.global_position.distance_to(nose) < 2.0:
			near = true
			spread = float((e[1] as ShaderMaterial).get_shader_parameter("spread"))
	_check(near and absf(fl.global_position.y) < 1e6 and fl.get_parent() is Node3D, "the pool lies under the nose, under the level root")
	_check(spread > 0.5, "a staged pool shows a minute's spread (%.2f)" % spread)
	_check(pole.find_child("RadiatorSteam", true, false) is CPUParticles3D, "the radiator steams")
	_check(pole.has_meta(&"aftermath_pool"), "once a car")


func _switch_off() -> void:
	CrashAftermath.enabled = false
	var c := _car(-10.0)
	await _ticks(30)
	var fl := CrashAftermath.instance()
	var before := fl.pools_made if fl else 0
	c.damage_state().stage("pole55")
	await _ticks(2)
	var cd := c._damage._crumple
	_check(cd != null and cd._crumple_shape[0].w < 0.5, "CRASH_AFTERMATH off: a pole hits like a wall")
	_check((fl.pools_made if fl else 0) == before and c.find_child("RadiatorSteam", true, false) == null, "and leaks nothing")
	CrashAftermath.enabled = true
