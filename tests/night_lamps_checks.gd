extends RefCounted
## The street lamps at eye level (NightLamps, LampShadows; docs/HANDOFF.md "The street lamps at eye
## level"), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the
## autoloads.
##
## Pins the pool's new profile (laid in the lamp's frame, stretched along the street for the arm
## heads, the old dot back with NIGHT_LAMPS=0), the shader's branch, the shadow budget per Quality
## level, the pure pick and fade, a staged run of the node itself (the two nearest lit lamps cast,
## fade in, hand over, fade out and stop), the lamp models moved off their lights' casters, and a
## FULL chunk's lamps in the shadow group. Stages what it needs and puts it back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := NightLamps.enabled
	NightLamps.enabled = true
	_pools()
	_shader()
	_budget()
	_pick()
	await _staged(city)
	_layer()
	_chunk(city)
	NightLamps.enabled = was


func _lamp(t: int) -> Dictionary:
	return StreetLamps.place(null, Vector3(100.0, 0.15, 40.0), Vector2(0.0, 1.0), t)


func _head(lp: Dictionary) -> Vector3:
	var h := Vector3.ZERO
	for l: Vector3 in lp.lights:
		h += l
	return h / float(lp.lights.size())


func _pools() -> void:
	var at := Vector3(100.0, 0.15, 40.0)
	var cobra := _lamp(StreetLamps.Type.COBRA)
	var post := _lamp(StreetLamps.Type.POST)
	var on: Array = NightLamps.pool_instance(cobra, _head(cobra), at)
	var xf: Transform3D = on[0]
	var custom: Color = on[2]
	var across := xf.basis.x
	var along := xf.basis.y
	# The lamp faces +z here: its arm (model +x) points to the street, so the quad's x does too.
	var street := (cobra.xform as Transform3D).basis.x.normalized()
	_t._check(across.normalized().dot(street) > 0.99 and absf(xf.basis.z.normalized().y) > 0.99,
		"night lamps: a cobra's pool lies flat in the lamp's frame, its x toward the street")
	_t._check(is_equal_approx(along.length() / across.length(), NightLamps.ARM_ASPECT) and is_equal_approx(custom.g, NightLamps.ARM_ASPECT)
		and custom.a == 1.0 and is_equal_approx(custom.b, NightLamps.ARM_BACK),
		"night lamps: an arm head's pool runs %.2fx along the street and is cut behind the pole" % (along.length() / across.length()))
	_t._check(is_equal_approx(across.length(), float(cobra.pool) * NightLamps.ACROSS * 2.0) and xf.origin.distance_to(Vector3(_head(cobra).x, at.y + 0.09, _head(cobra).z)) < 0.001,
		"night lamps: the pool is centred under the head, %.1f m across" % across.length())
	var hr := (_head(cobra).y - at.y) / (float(cobra.pool) * NightLamps.ACROSS)
	_t._check(is_equal_approx(custom.r, hr), "night lamps: the pool carries the head's height over its radius (%.2f)" % custom.r)
	var p: Array = NightLamps.pool_instance(post, _head(post), at)
	var pc: Color = p[2]
	_t._check(pc.b == 0.0 and pc.g == 1.0 and is_equal_approx((p[0] as Transform3D).basis.x.length(), (p[0] as Transform3D).basis.y.length()),
		"night lamps: a post-top's pool is round with no shield")
	var col: Color = on[1]
	var old_col := StreetLamps.pool_color(StreetLamps.Type.COBRA, Vector2(at.x, at.z))
	_t._check(col.r < old_col.r and col.r > 0.0, "night lamps: the broad pool is dimmer per square metre than the old dot (%.2f < %.2f)" % [col.r, old_col.r])
	NightLamps.enabled = false
	var off: Array = NightLamps.pool_instance(cobra, _head(cobra), at)
	NightLamps.enabled = true
	var size: float = cobra.pool
	var want := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(_head(cobra).x, at.y + 0.09, _head(cobra).z))
	_t._check((off[0] as Transform3D).is_equal_approx(want) and (off[1] as Color) == old_col and (off[2] as Color) == Color.BLACK,
		"night lamps: NIGHT_LAMPS=0 lays the old dot (old transform, colour, no custom)")


func _shader() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/light_pool.gdshader")
	_t._check(s.contains("v_custom = INSTANCE_CUSTOM;") and s.contains("if (v_custom.a > 0.5)") and s.contains("pow(1.0 + d2, -1.5)"),
		"night lamps: light_pool.gdshader draws the street lamps' pools as a point source's falloff, every other pool as before")
	var src := FileAccess.get_file_as_string("res://scripts/world/city_chunk.gd")
	_t._check(src.contains("NightLamps.pool_instance(lp, head, at)") and src.contains("light.add_to_group(LampShadows.GROUP)"),
		"night lamps: CityChunk lays the new pool and puts its lamps in the shadow group")


func _budget() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/util/quality.gd")
	_t._check(src.contains("LampShadows.budget = [2, 0, 0, 0][int(level)]"), "night lamps: two shadowed lamps at HIGH, none below (Quality)")
	_t._check(not LampShadows.supported() or LampShadows.force or RenderingServer.get_current_rendering_method() == "forward_plus",
		"night lamps: lamp shadows only where the renderer is Forward+")


func _pick() -> void:
	var cam := Vector3.ZERO
	var pos: Array = [Vector3(20, 5, 0), Vector3(5, 5, 0), Vector3(3, 5, 0), Vector3(10, 5, 0), Vector3(50, 5, 0)]
	var lit: Array = [true, true, false, true, true]
	var got: Array = LampShadows.pick(cam, pos, lit, 2, 34.0)
	_t._check(got == [1, 3], "night lamps: the pick is the two nearest LIT lamps within reach (%s)" % [got])
	_t._check(LampShadows.pick(cam, pos, lit, 0, 34.0).is_empty(), "night lamps: a zero budget picks none")
	var w0 := LampShadows.weight_at(5.0, 34.0, 0.35)
	var w1 := LampShadows.weight_at(30.0, 34.0, 0.35)
	var w2 := LampShadows.weight_at(40.0, 34.0, 0.35)
	_t._check(is_equal_approx(w0, 1.0) and w1 > 0.0 and w1 < 1.0 and w2 == 0.0, "night lamps: a shadow fades out toward its reach (%.2f, %.2f, %.2f)" % [w0, w1, w2])


## The node itself on a staged street: lights round the city's camera, the node's own pick and
## fade run by hand (the renderer here is the dummy, so supported() is false and ensure() makes
## none: the node is made directly).
func _staged(city: Node3D) -> void:
	var cam := city.get_viewport().get_camera_3d()
	if cam == null:
		_t._check(false, "night lamps: the city has a camera")
		return
	var base := cam.global_position
	var holder := Node3D.new()
	city.add_child(holder)
	var lights: Array = []
	for d: float in [4.0, 9.0, 16.0, 60.0]:
		var l := OmniLight3D.new()
		l.light_energy = 2.0
		l.add_to_group(LampShadows.GROUP)
		holder.add_child(l)
		l.global_position = base + Vector3(d, 6.0, 0.0)
		lights.append(l)
	var dark := OmniLight3D.new()
	dark.light_energy = 0.0
	dark.add_to_group(LampShadows.GROUP)
	holder.add_child(dark)
	dark.global_position = base + Vector3(2.0, 6.0, 0.0)
	var b0 := LampShadows.budget
	LampShadows.budget = 2
	var node := LampShadows.new()
	holder.add_child(node)
	node.set_process(false)
	node.call("_pick", base)
	for i in 20:
		node.call("_process", 0.05)
	var l0: OmniLight3D = lights[0]
	var l1: OmniLight3D = lights[1]
	_t._check(l0.shadow_enabled and l1.shadow_enabled and not (lights[2] as OmniLight3D).shadow_enabled and not (lights[3] as OmniLight3D).shadow_enabled and not dark.shadow_enabled,
		"night lamps: the two nearest lit lamps cast, the dark one and the far ones do not")
	_t._check(l0.shadow_opacity > 0.95 and LampShadows.active_count == 2, "night lamps: their shadows have faded in (%.2f, %d casting)" % [l0.shadow_opacity, LampShadows.active_count])
	_t._check(l0.shadow_caster_mask & LampShadows.LAMP_LAYER == 0 and l0.shadow_caster_mask & 1 != 0,
		"night lamps: a shadowed lamp's light leaves the lamp models' layer out of its casters")
	# The nearest one goes dark: the next lamp takes over, the old one fades rather than pops.
	l0.light_energy = 0.0
	node.call("_pick", base)
	node.call("_process", 0.1)
	var mid := l0.shadow_opacity
	for i in 20:
		node.call("_process", 0.05)
	_t._check(mid > 0.05 and mid < 0.95 and not l0.shadow_enabled and (lights[2] as OmniLight3D).shadow_enabled,
		"night lamps: a hand-over fades the old shadow out (%.2f mid-way) and the next lamp's in" % mid)
	LampShadows.budget = 0
	node.call("_pick", base)
	for i in 20:
		node.call("_process", 0.05)
	var any := false
	for l: OmniLight3D in lights:
		any = any or l.shadow_enabled
	_t._check(not any and LampShadows.active_count == 0, "night lamps: a zero budget (below HIGH) leaves no lamp casting")
	LampShadows.budget = b0
	holder.queue_free()
	await city.get_tree().process_frame


func _layer() -> void:
	var holder := Node3D.new()
	for nm: String in ["Batch_lamp_cobra", "BatchShadow_lamp_cobra", "Batch_lamp_pool", "Batch_bw_lamp", "Batch_tree_0", "Batch_atmos_glow_halo"]:
		var mi := MultiMeshInstance3D.new()
		mi.name = nm
		holder.add_child(mi)
	var moved := LampShadows.lamp_layer(holder)
	var ok := true
	for c in holder.get_children():
		var on_layer := (c as VisualInstance3D).layers == LampShadows.LAMP_LAYER
		var should := String(c.name) in ["Batch_lamp_cobra", "BatchShadow_lamp_cobra", "Batch_bw_lamp"]
		ok = ok and on_layer == should
	holder.free()
	_t._check(ok and moved == 3, "night lamps: the lamp models (and twins) move to their own layer, the pools and everything else stay (%d)" % moved)


func _chunk(city: Node3D) -> void:
	var plan = city.get("plan")
	if plan == null or not city.has_method("_new_chunk"):
		_t._check(false, "night lamps: the city builds chunks")
		return
	var k: Vector2i = plan.chunk_index_at(Vector2(2984.0, 170.0))
	var chunk: Node3D = city.call("_new_chunk", k, 0)
	chunk.build()
	var lamps := 0
	for r: Dictionary in chunk.get("prop_records"):
		if r.kind == "lamp":
			lamps += 1
	var grouped := 0
	for c in chunk.get_children():
		if c is OmniLight3D and (c as Node).is_in_group(LampShadows.GROUP):
			grouped += 1
	chunk.queue_free()
	_t._check(grouped > 4 and grouped <= lamps, "night lamps: every street lamp of a FULL downtown chunk is in the shadow group (%d of %d)" % [grouped, lamps])
