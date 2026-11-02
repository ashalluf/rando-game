extends RefCounted
## The freeway at night (FreewayNight, wave 6 refcam `freeway_night`) for tests/smoke_test.gd.
## Checks: the light standards' heads are where FreewayKit builds them (every LIGHT_EVERY-th
## segment, both arms, HEAD_H over the deck, nearest first, none under the stack's decks); the pool
## material carries the cobra numbers and the A/B zeroes them; the cobra pool's quad stays on the
## deck; the shader's cobra branch is there and its default is off; a FULL freeway chunk's deck is
## on DECK_LAYER and the lights' cull mask leaves it out; the lights' budget; freeway cars' lamps
## reach FAR_LIGHTS and a street car's go back to Vehicle's 160. Leans on nothing an earlier check
## left: it stages its own freeway car.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	_heads(plan)
	_materials()
	await _live(city, plan)


func _heads(plan: CityPlan) -> void:
	_t._check(FreewayNight.enabled, "freeway night: on by default (FREEWAY_NIGHT=0 is the A/B)")
	var at := Vector2(1795.8, 1092.3)
	var heads: Array = FreewayNight.heads_near(plan, at, 240.0)
	_t._check(heads.size() >= 12, "freeway night: the 110 by the camera has light standards' heads (%d)" % heads.size())
	if heads.is_empty():
		return
	var sorted := true
	for i in range(1, heads.size()):
		if float(heads[i].d) < float(heads[i - 1].d) - 0.001:
			sorted = false
	_t._check(sorted, "freeway night: heads come nearest first")
	# Pairs 2 x (LIGHT_ARM + 0.35) apart (both arms of one standard), standards LIGHT_EVERY steps apart.
	var fw: Freeway = plan.macro.freeway
	var pair_ok := false
	var spacing_ok := false
	for i in heads.size():
		for j in heads.size():
			if i == j:
				continue
			var d := Vector2(heads[i].pos.x, heads[i].pos.z).distance_to(Vector2(heads[j].pos.x, heads[j].pos.z))
			if absf(d - 2.0 * (FreewayKit.LIGHT_ARM + 0.35)) < 0.05:
				pair_ok = true
			if absf(d - float(FreewayKit.LIGHT_EVERY) * Freeway.STEP) < 1.5:
				spacing_ok = true
	_t._check(pair_ok and spacing_ok, "freeway night: two heads a standard, standards %d m apart" % int(FreewayKit.LIGHT_EVERY * Freeway.STEP))
	# Each head HEAD_H over the deck of the route it stands on.
	var h: Dictionary = heads[0]
	var tz: Array = fw.nearest_on(3, Vector2(h.pos.x, h.pos.z))
	var deck_y: float = (fw.point_at(3, float(tz[0]))[0] as Vector3).y
	_t._check(absf(float(h.pos.y) - deck_y - FreewayNight.HEAD_H) < 0.6,
		"freeway night: a head stands HEAD_H over its deck (%.2f over)" % (float(h.pos.y) - deck_y))
	# The cobra pool stays on the deck: from the head's foot across to the deck edge on its side.
	var lay := Freeway.lane_layout(float(fw.routes[3].width))
	_t._check(FreewayNight.POOL_SIZE.y * 0.5 <= float(lay.outer) - (FreewayKit.LIGHT_ARM + 0.35) + 0.5,
		"freeway night: the cobra pool's quad keeps to the deck (%.1f m across)" % FreewayNight.POOL_SIZE.y)
	_t._check(FreewayNight.POOL_SIZE.x > float(FreewayKit.LIGHT_EVERY) * Freeway.STEP,
		"freeway night: neighbouring standards' pools overlap along the road")
	# None under the stack's upper decks.
	var st: FreewayStack = fw.stack
	if st != null and not st.covered.is_empty():
		var c: Vector2i = st.covered.keys()[0]
		var seg_a: Vector2 = fw.routes[c.x].points[c.y]
		var bad := 0
		for hh: Dictionary in FreewayNight.heads_near(plan, seg_a, 60.0):
			for k in st.covered.keys():
				var kk: Vector2i = k
				if kk.y % FreewayKit.LIGHT_EVERY != 1:
					continue
				var p: Vector2 = fw.routes[kk.x].points[kk.y]
				if Vector2(hh.pos.x, hh.pos.z).distance_to(p) < FreewayKit.LIGHT_ARM + 0.5:
					bad += 1
		_t._check(bad == 0, "freeway night: no head under the stack's upper decks (%d)" % bad)


func _materials() -> void:
	var mat := FreewayKit.pool_material()
	var cs: Vector4 = mat.get_shader_parameter("cobra_size")
	_t._check(is_equal_approx(cs.x, FreewayNight.HEAD_H) and is_equal_approx(cs.y, FreewayNight.POOL_SIZE.x)
		and is_equal_approx(cs.z, FreewayNight.POOL_SIZE.y), "freeway night: the pool material carries the cobra numbers (%s)" % str(cs))
	var probe := ShaderMaterial.new()
	probe.shader = mat.shader
	FreewayNight.enabled = false
	FreewayNight.dress_pool(probe)
	FreewayNight.enabled = true
	_t._check((probe.get_shader_parameter("cobra_size") as Vector4) == Vector4.ZERO, "freeway night: its A/B zeroes the cobra numbers")
	var src := FileAccess.get_file_as_string("res://shaders/light_pool.gdshader")
	_t._check(src.contains("uniform vec4 cobra_size = vec4(0.0);") and src.contains("UV.x > 3.5 && cobra_size.x > 0.0"),
		"freeway night: light_pool's cobra branch is there and off by default")
	_t._check(FreewayNight.budget() >= 0 and FreewayNight.budget() <= 8, "freeway night: a small light budget (%d)" % FreewayNight.budget())


func _live(city: Node3D, plan: CityPlan) -> void:
	var tm: Node = city.get_node_or_null("Traffic")
	if tm == null:
		_t._check(false, "freeway night: no Traffic node")
		return
	# A FULL chunk with freeway deck: its deck on DECK_LAYER.
	var deck_ok := false
	var decks := 0
	for ch in city.get_children():
		var d := ch.get_node_or_null("FreewayDeck") as MeshInstance3D
		if d == null:
			continue
		decks += 1
		if d.layers == FreewayNight.DECK_LAYER:
			deck_ok = true
	_t._check(decks == 0 or deck_ok, "freeway night: a freeway chunk's deck is on its own layer (%d decks)" % decks)
	var inst := FreewayNight.instance()
	# A placed freeway car's lamps reach FAR_LIGHTS once the node deals; a street car's 160.
	var fw: Freeway = plan.macro.freeway
	var player := _t.get_tree().get_first_node_in_group("player") as Node3D
	var ws := _t.get_node("/root/WorldState")
	var at: Vector3 = ws.call("to_world", player.global_position) if player else Vector3.ZERO
	var tz: Array = fw.nearest_on(3, Vector2(at.x, at.z))
	var car: Node3D = tm.call("place_freeway_car", 3, float(tz[0]), 1)
	if inst == null:
		inst = FreewayNight.new()
		inst.name = "FreewayNightCheck"
		city.add_child(inst)
		await _t.get_tree().process_frame
	inst.update_now()
	var mask_ok := true
	for l in inst.get_children():
		if l is OmniLight3D and ((l as OmniLight3D).light_cull_mask & FreewayNight.DECK_LAYER) != 0:
			mask_ok = false
	_t._check(mask_ok and inst.get_child_count() == FreewayNight.budget(),
		"freeway night: %d lights, all leaving the deck to its pools" % inst.get_child_count())
	var nl: MeshInstance3D = car.get("_night_lights") if car else null
	_t._check(nl != null and is_equal_approx(nl.visibility_range_end, FreewayNight.FAR_LIGHTS),
		"freeway night: a freeway car's lamps reach %.0f m" % FreewayNight.FAR_LIGHTS)
	var street: Array = tm.get("cars")
	var street_ok := true
	for c in street:
		var snl: Variant = (c as Node).get("_night_lights") if is_instance_valid(c) else null
		if snl is MeshInstance3D and not is_equal_approx((snl as MeshInstance3D).visibility_range_end, FreewayNight.NEAR_LIGHTS):
			street_ok = false
	_t._check(street_ok, "freeway night: street cars keep 160 m lamps (%d)" % street.size())
	if car:
		(tm.get("freeway_cars") as Array).erase(car)
		tm.call("_retire", car)
	if inst.name == "FreewayNightCheck":
		inst.queue_free()
	await _t.get_tree().process_frame
