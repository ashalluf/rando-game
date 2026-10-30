extends RefCounted
## The wet world (WetWorld, CarWipers, shaders/wet_surface.gdshaderinc), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks that every shader the rain reaches includes the shared water and calls it only behind the
## one dry branch (`ws_on()`), spends no sampler (the web's budget), and that the GDScript mirrors
## (WetWorld.wall(), CarWipers.angle_at()) still say what the shader says; that a wall wets from the
## top down while it rains, faster down its streaks, with the foot wet at once, and dries open wall
## first; the `wet_world` global and its switch; then builds cars on a deck in the air: a parked car
## has its wipers parked on the shared glass, a driven one runs them on a phase its own glass copy
## shares, the blades stand on the windscreen's foot inside its pane, and with the switch off no
## wipers are built. Weather, the switch and the player are put back.

const SHADERS := [
	"res://shaders/car_paint.gdshaderinc", "res://shaders/car_glass.gdshader",
	"res://shaders/car_glass_damage.gdshader", "res://shaders/car_wiper.gdshader",
	"res://shaders/car_glass_open.gdshader",
	"res://shaders/building.gdshader", "res://shaders/building_lod.gdshader",
	"res://shaders/facade_kit.gdshaderinc", "res://shaders/rooftop.gdshader",
	"res://shaders/character.gdshader", "res://shaders/crowd_hair.gdshader",
	"res://shaders/hero_cloth.gdshader", "res://shaders/hero_hair.gdshader",
]

var _t: Object
var _tree: SceneTree
var _city: Node3D
var _top := Vector3.ZERO
var _deck: StaticBody3D
var _cars: Array[Vehicle] = []


func run(t: Object, city: Node3D) -> void:
	_t = t
	_tree = (t as Node).get_tree()
	_city = city
	var enabled_was := WetWorld.enabled
	_sources()
	_mirrors()
	_wall()
	_switch()
	_shelter()
	await _wipers()
	WetWorld.set_enabled(enabled_was)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _sources() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/wet_surface.gdshaderinc")
	_check(not inc.contains("sampler2D") and not FileAccess.get_file_as_string("res://shaders/car_wipers.gdshaderinc").contains("sampler2D")
		and not FileAccess.get_file_as_string("res://shaders/car_glass_wet.gdshaderinc").contains("sampler2D"),
		"the wet world's includes spend no sampler (the web's budget)")
	var bad := []
	for p: String in SHADERS:
		var s := FileAccess.get_file_as_string(p)
		var direct := s.contains("wet_surface.gdshaderinc") or s.contains("car_glass_wet.gdshaderinc")
		var gated := s.contains("if (ws_on()") or s.contains("ws_on() &&")
		if not direct or not gated:
			bad.append(p.get_file())
	_check(bad.is_empty(), "every wet shader includes the shared water and runs it behind ws_on() (bad: %s)" % [bad])
	# The far and near walls take the same rule.
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var far := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	_check(near.contains("ws_wall(wet_down, up, streak)") and far.contains("ws_wall(down, up, streak)"),
		"the near and far buildings wet their walls by the same ws_wall()")
	var cfg := FileAccess.get_file_as_string("res://project.godot")
	_check(cfg.contains("wet_world={"), "project.godot declares the wet_world shader global")
	for p: String in ["res://shaders/car_glass.gdshader", "res://shaders/car_wiper.gdshader"]:
		var sh: Shader = load(p)
		var names := []
		for u: Dictionary in sh.get_shader_uniform_list():
			names.append(String(u.name))
		_check(names.has("wipers_on") and names.has("wiper_phase") and names.has("wiper_pivot_a"),
			"%s compiles with the wiper uniforms" % p.get_file())


func _mirrors() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/wet_surface.gdshaderinc")
	_check(inc.contains("float reach = w * 60.0 + streak * w * 40.0 + 1.5;")
		and inc.contains("float driven = 0.6 * smoothstep(0.45, 1.0, w);")
		and inc.contains("float splash = (1.0 - smoothstep(0.35, 0.9, up)) * smoothstep(0.0, 0.15, w);")
		and inc.contains("float t = (1.0 - clamp(hold, 0.0, 1.0)) * 0.85;")
		and inc.contains("float drying = ws_dry(0.2 + 0.55 * streak + 0.5 * (1.0 - smoothstep(0.3, 1.2, up)));"),
		"WetWorld.wall() / dry() mirror ws_wall() / ws_dry()")
	var wip := FileAccess.get_file_as_string("res://shaders/car_wipers.gdshaderinc")
	_check(wip.contains("const float WIPER_STROKE = %s;" % str(CarWipers.STROKE))
		and wip.contains("return mix(3.6, 1.12, smoothstep(0.25, 0.7, ws_rain()));"),
		"CarWipers.angle_at() mirrors wiper_angle() (stroke %.2f s)" % CarWipers.STROKE)
	# The cycle: parked at its start, up at the top after one stroke, back down after two.
	var top := CarWipers.angle_at(CarWipers.STROKE, 0.0, 1.0)
	var back := CarWipers.angle_at(2.0 * CarWipers.STROKE + 0.01, 0.0, 1.0)
	_check(CarWipers.angle_at(0.0, 0.0, 1.0) < 0.01 and absf(top - CarWipers.SWEEP) < 1e-3 and back < 0.01
		and CarWipers.angle_at(0.3, 0.0, 0.0) == 0.0 and CarWipers.period(1.0) < CarWipers.period(0.2),
		"the wipers sweep up and back each cycle, rest parked when it is dry, run faster in a downpour")
	_check(absf(CarWipers.angle_at(0.2, 0.25, 1.0) - CarWipers.angle_at(0.2 + 0.25 * CarWipers.period(1.0), 0.0, 1.0)) < 1e-4,
		"a phase bucket is a fraction of the cycle")


func _wall() -> void:
	# Early in the rain the top of a wall is wet and its foot only splashed; a streak runs ahead.
	var top := WetWorld.wall(1.0, 20.0, 0.0, 0.15, 0.0)
	var mid := WetWorld.wall(15.0, 6.0, 0.0, 0.15, 0.0)
	var mid_streak := WetWorld.wall(15.0, 6.0, 1.0, 0.15, 0.0)
	var tall := WetWorld.wall(200.0, 100.0, 0.0, 1.0, 0.0)
	var foot := WetWorld.wall(20.0, 0.2, 0.0, 0.15, 0.0)
	_check(top > 0.7 and mid < 0.1 and mid_streak > mid + 0.4 and foot > 0.6,
		"a wall wets from the top down, faster down a streak, its foot splashed (top %.2f mid %.2f streak %.2f foot %.2f)" % [top, mid, mid_streak, foot])
	var soaked := WetWorld.wall(30.0, 6.0, 0.0, 1.0, 0.0)
	_check(soaked > 0.75 and tall > 0.5 and tall < 0.7, "a downpour soaks the wall to 30 m down (%.2f) and a tower's whole height part way (%.2f)" % [soaked, tall])
	# Drying, half the water gone: the open wall is dry, a streak and the foot still wet.
	var open := WetWorld.wall(10.0, 6.0, 0.0, 0.45, 1.0)
	var streak := WetWorld.wall(10.0, 6.0, 1.0, 0.45, 1.0)
	var foot2 := WetWorld.wall(10.0, 0.1, 0.0, 0.45, 1.0)
	_check(open < 0.2 and streak > 0.8 and foot2 > open + 0.3,
		"drying, the open wall goes first and the streaks and the foot last (%.2f / %.2f / %.2f)" % [open, streak, foot2])
	_check(WetWorld.wall(10.0, 6.0, 1.0, 0.0, 1.0) == 0.0 and WetWorld.wall(10.0, 0.1, 1.0, 0.0, 0.0) == 0.0,
		"a dry city has dry walls")


func _switch() -> void:
	WetWorld.set_enabled(false)
	var off: Variant = RenderingServer.global_shader_parameter_get("wet_world")
	WetWorld.set_enabled(true)
	var on: Variant = RenderingServer.global_shader_parameter_get("wet_world")
	# The dummy renderer may keep no globals; then only the flag is checked.
	_check((off == null or float(off) == 0.0) and (on == null or float(on) == 1.0) and WetWorld.enabled,
		"WET_WORLD's switch drives the wet_world global (off %s, on %s)" % [off, on])


func _shelter() -> void:
	# A person under an open umbrella wears the sheltered copy of their look, and back when it folds.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	var who := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	who.add_child(mi)
	WetWorld.shelter(who, true)
	var under := mi.material_override as ShaderMaterial
	var again := WetWorld.sheltered_material(mat)
	WetWorld.shelter(who, false)
	_check(under != mat and under == again and float(under.get_shader_parameter("rain_shelter")) == 1.0
		and mi.material_override == mat, "an open umbrella swaps the look for its one shared sheltered copy, folded back again")
	who.free()


func _wipers() -> void:
	var player := _tree.get_first_node_in_group("player") as Player
	var ws: Node = _tree.root.get_node("/root/WorldState")
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 340.0, 60.0)
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO

	WetWorld.set_enabled(true)
	var parked := _car(-6.0, Vehicle.BodyType.SEDAN)
	var driven := _car(6.0, Vehicle.BodyType.SEDAN)
	await _ticks(3)
	driven._npc_driver = true
	driven._update_occupant(true)
	await _ticks(1)
	var pm := _blades(parked)
	var dm := _blades(driven)
	_check(pm != null and dm != null, "a sedan carries a wiper pair under its glass")
	if pm != null and dm != null:
		var pmat := pm.material_override as ShaderMaterial
		var dmat := dm.material_override as ShaderMaterial
		_check(pmat != null and float(pmat.get_shader_parameter("wipers_on")) == 0.0 and pm.mesh == dm.mesh,
			"a parked car's wipers rest, on the body type's one shared mesh")
		var glass := driven.cabin_glass() as ShaderMaterial
		var phase := float(dmat.get_shader_parameter("wiper_phase")) if dmat else -1.0
		_check(dmat != null and float(dmat.get_shader_parameter("wipers_on")) == 1.0 and glass != null
			and float(glass.get_shader_parameter("wipers_on")) == 1.0
			and absf(float(glass.get_shader_parameter("wiper_phase")) - phase) < 1e-6
			and glass.get_shader_parameter("wiper_pivot_a") == dmat.get_shader_parameter("wiper_pivot_a"),
			"a driven car runs its wipers and its glass clears the beads on the same phase and pivots")
		var pglass := parked.cabin_glass() as ShaderMaterial
		_check(pglass != null and float(pglass.get_shader_parameter("wipers_on")) == 0.0
			and (pglass.get_shader_parameter("wiper_reach") as Vector2).y > 0.0,
			"the shared glass of the parked body knows its wipers but keeps them still")
		_check(dm.get_parent() is MeshInstance3D and dm.transform == Transform3D.IDENTITY
			and dm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and dm.visibility_range_end > 0.0,
			"the blades sit in the glass mesh's own space, cast no shadow and stop drawing with distance")
		_geometry(driven, dmat)
	# A car built with the switch off has none.
	WetWorld.set_enabled(false)
	var off_car := _car(-18.0, Vehicle.BodyType.SEDAN)
	await _ticks(2)
	_check(_blades(off_car) == null, "with WET_WORLD=0 no wipers are built")
	WetWorld.set_enabled(true)

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _ticks(2)


## The pivots on the windscreen's foot, inside its pane (mesh space), the reach a real blade's.
func _geometry(car: Vehicle, mat: ShaderMaterial) -> void:
	var data := CarCabin.for_car(car)
	var screen: Array = []
	for p: Array in data.panes:
		if int(p[3]) == CarCabin.KIND_SCREEN:
			screen = p
	if screen.is_empty():
		_check(false, "the sedan has a windscreen pane")
		return
	var lo: Vector3 = screen[0]
	var hi: Vector3 = screen[1]
	var box := AABB(lo, hi - lo).grow((hi - lo).length() * 0.08)
	var pa: Vector3 = mat.get_shader_parameter("wiper_pivot_a")
	var pb: Vector3 = mat.get_shader_parameter("wiper_pivot_b")
	var reach: Vector2 = mat.get_shader_parameter("wiper_reach")
	var u: Vector3 = mat.get_shader_parameter("wiper_u")
	var v: Vector3 = mat.get_shader_parameter("wiper_v")
	var size := (hi - lo).length()
	_check(box.has_point(pa) and box.has_point(pb) and (pb - pa).dot(u) > 0.0
		and absf((pb - pa).dot(v)) < size * 0.05,
		"both pivots stand along the windscreen's foot, inside its pane")
	_check(reach.x >= 0.0 and reach.y > reach.x and reach.y < size and absf(u.dot(v)) < 1e-3,
		"the blades reach %.2f - %.2f mesh units over a %.2f screen, in an orthogonal frame" % [reach.x, reach.y, size])


func _car(x: float, type: int) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.3, 0.3, 0.32), Vehicle.Addon.NONE)
	car.position = _city.to_local(_top + Vector3(x, 0.9, 0.0))
	_city.add_child(car)
	_cars.append(car)
	return car


func _blades(car: Vehicle) -> MeshInstance3D:
	if not car.has_meta("wipers"):
		return null
	var mi: Variant = car.get_meta("wipers")
	return mi as MeshInstance3D if is_instance_valid(mi) else null
