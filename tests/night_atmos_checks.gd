extends RefCounted
## The night street's air (NightAtmos: halos, shafts, lens streaks, the canyon's sodium haze), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the pure rules (the haze per weather - a Santa Ana night driest, rain and the marine
## layer wettest -, shafts only where volumetric fog is off, the sodium haze only near the street
## at night), the shaders and the global they read, the instance builders (a halo per light, one
## shaft per FULL lamp, keys PropBreak treats as light), then builds a downtown FULL chunk and
## checks the halo, shaft and shop-glow batches (shadowless, every lamp's halo in its own prop
## record so a popped lamp takes it), the same chunk with the A/B off (same lamps and ids, no
## atmosphere batches), the node pushing the global for a staged rainy night and back, and the
## fog lean never accumulating frame to frame. Stages everything it needs and puts it back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := NightAtmos.enabled
	NightAtmos.enabled = true
	_rules()
	_assets()
	_builders()
	_chunk(city)
	_node(city)
	NightAtmos.enabled = was


func _rules() -> void:
	var clear := NightAtmos.haze_for(0, 0, 1.0, 0.0, 0.0, 0.0)
	var rain := NightAtmos.haze_for(2, 2, 1.0, 0.9, 0.0, 0.8)
	var storm := NightAtmos.haze_for(3, 3, 1.0, 1.0, 0.0, 1.0)
	var marine := NightAtmos.haze_for(4, 4, 1.0, 0.0, 1.0, 0.0)
	var santa := NightAtmos.haze_for(5, 5, 1.0, 0.0, 0.0, 0.5)
	_t._check(santa < 0.15 and santa < clear and clear < rain and rain <= storm and marine > 0.85,
		"night haze: Santa Ana %.2f < clear %.2f < rain %.2f <= storm %.2f, marine layer %.2f" % [santa, clear, rain, storm, marine])
	var half := NightAtmos.haze_for(2, 0, 0.5, 0.45, 0.0, 0.0)
	_t._check(half > clear and half < rain and is_equal_approx(half, NightAtmos.haze_for(2, 0, 0.5, 0.45, 0.0, 0.0)),
		"the haze blends between weathers and is pure (%.2f)" % half)
	_t._check(NightAtmos.haze_for(0, 0, 1.0, 0.0, 0.0, 1.0) > clear and NightAtmos.haze_for(0, 0, 1.0, 0.0, 0.7, 0.0) > clear,
		"a soaked street and the marine layer at the camera thicken a clear night's air")
	_t._check(NightAtmos.shaft_gain_for(true) == 0.0 and NightAtmos.shaft_gain_for(false) == 1.0,
		"shafts are drawn only where volumetric fog is off (never doubled)")
	_t._check(NightAtmos.halo_gain_for(0) == 1.0 and NightAtmos.halo_gain_for(3) < 1.0, "the lowest quality dims the halos")
	var street := NightAtmos.sodium_for(1.0, 0.9, 2.0)
	var day := NightAtmos.sodium_for(0.0, 0.9, 2.0)
	var air := NightAtmos.sodium_for(1.0, 0.9, NightAtmos.SODIUM_TOP + 10.0)
	var dry := NightAtmos.sodium_for(1.0, 0.06, 2.0)
	_t._check(street.x > 0.3 and street.y > 0.0 and day == Vector2.ZERO and air == Vector2.ZERO and dry.x < street.x * 0.2,
		"the sodium haze is a wet night street's (lean %.2f; none by day, high above or much on a dry night %.3f)" % [street.x, dry.x])


func _assets() -> void:
	var pg := FileAccess.get_file_as_string("res://project.godot")
	_t._check(pg.contains("night_atmos={"), "project.godot declares the night_atmos shader global")
	var inc := FileAccess.get_file_as_string("res://shaders/night_halo.gdshaderinc")
	var halo := FileAccess.get_file_as_string("res://shaders/night_halo.gdshader")
	var shaft := FileAccess.get_file_as_string("res://shaders/night_shaft.gdshader")
	var car := FileAccess.get_file_as_string("res://shaders/car_lights.gdshader")
	_t._check(inc.contains("global uniform vec4 night_atmos;") and halo.contains("night_halo.gdshaderinc") and shaft.contains("night_halo.gdshaderinc")
		and car.contains("night_halo.gdshaderinc"), "the halo, shaft and car lamp shaders share night_halo.gdshaderinc")
	_t._check(halo.contains("fog_disabled") and shaft.contains("fog_disabled") and halo.contains("blend_add") and shaft.contains("blend_add"),
		"halos and shafts are additive and fog-free (fog would add its colour to them)")
	_t._check(car.contains("step(%d.5, part)" % (PropFactory.LIGHT_HALO_TAIL - 1)) and car.contains("part > %d.5" % (PropFactory.LIGHT_HALO_HEAD - 1)),
		"car_lights.gdshader's halo parts are PropFactory.LIGHT_HALO_HEAD / _TAIL (%d, %d)" % [PropFactory.LIGHT_HALO_HEAD, PropFactory.LIGHT_HALO_TAIL])
	var hm := NightAtmos.halo_mesh()
	var sm := NightAtmos.shaft_mesh()
	_t._check(hm.get_surface_count() == 1 and hm.surface_get_material(0) == NightAtmos.atmos_material("halo") and hm.custom_aabb.size.x >= 8.0,
		"the halo is one quad on the halo shader with bounds for its largest glow")
	_t._check(sm.get_surface_count() == 1 and sm.surface_get_material(0) == NightAtmos.atmos_material("shaft") and absf(sm.get_aabb().position.y + 1.0) < 0.01
		and absf(sm.get_aabb().end.y) < 0.01, "the shaft is one open unit cone on the shaft shader, top at 0, floor at -1")
	_t._check((NightAtmos.atmos_material("halo").shader as Shader).code.contains("skip_vertex_transform"), "the halo turns itself to the camera in its vertex stage")


func _builders() -> void:
	var lights := [Vector3(10.0, 7.5, 3.0), Vector3(12.0, 7.5, 3.0)]
	var full := NightAtmos.lamp_parts(lights, Vector3(11.0, 7.5, 3.0), 0.2, 12.0, Vector2(10.0, 3.0), true)
	var lod := NightAtmos.lamp_parts(lights, Vector3(11.0, 7.5, 3.0), 0.2, 12.0, Vector2(10.0, 3.0), false)
	var halos := 0
	var shafts := 0
	var glow_keys := true
	for p: Array in full:
		halos += 1 if p[0] == NightAtmos.HALO_KEY else 0
		shafts += 1 if p[0] == NightAtmos.SHAFT_KEY else 0
		glow_keys = glow_keys and PropBreak._is_glow(String(p[0]))
	_t._check(halos == 2 and shafts == 1 and lod.size() == 2 and glow_keys,
		"a twin lamp gets a halo per globe and one shaft (FULL), halos only at LOD, keys PropBreak treats as light")
	var s: Array = full.filter(func(p: Array) -> bool: return p[0] == NightAtmos.SHAFT_KEY)[0]
	var xf: Transform3D = s[2]
	_t._check(absf(xf.basis.get_scale().y - (7.5 - 0.2)) < 0.01 and xf.basis.get_scale().x >= 1.2,
		"the shaft runs from the head to the pavement (%.2f m tall, %.2f m foot)" % [xf.basis.get_scale().y, xf.basis.get_scale().x])
	var shop: Variant = NightAtmos.shop_part(Transform3D(Basis(Vector3(6.0, 0, 0), Vector3(0, 0, 8.0), Vector3(0, -1, 0)), Vector3(5, 0.2, 5)), Color(1, 0.8, 0.6, 0.7), 0.2)
	_t._check(shop is Array and (shop as Array)[0] == NightAtmos.SHOP_KEY and absf(((shop as Array)[2] as Transform3D).origin.y - (0.2 + NightAtmos.SHOP_HALO_Y)) < 0.01
		and ((shop as Array)[4] as Color).g == 1.0, "a lit shop front's glow sits at its window, out over the pavement, kind 1")
	NightAtmos.enabled = false
	var off := NightAtmos.lamp_parts(lights, Vector3(11.0, 7.5, 3.0), 0.2, 12.0, Vector2(10.0, 3.0), true)
	NightAtmos.enabled = true
	_t._check(off.is_empty(), "NIGHT_ATMOS=0 builds no halo or shaft")


func _records(chunk: CityChunk) -> Array:
	var out := []
	for r: Dictionary in chunk.prop_records:
		out.append([r.id, (r.position as Vector3).snapped(Vector3(0.01, 0.01, 0.01))])
	return out


func _chunk(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	var k := plan.chunk_index_at(Vector2(1866.6, 660.0))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var lamps := 0
	var lights := 0
	var with_halo := 0
	var with_shaft := 0
	var popped: Dictionary = {}
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != "lamp":
			continue
		lamps += 1
		var h := 0
		var s := 0
		for e: Array in r.instances:
			h += 1 if e[0] == NightAtmos.HALO_KEY else 0
			s += 1 if e[0] == NightAtmos.SHAFT_KEY else 0
		lights += h
		with_halo += 1 if h > 0 else 0
		with_shaft += 1 if s == 1 else 0
		if popped.is_empty() and h > 0:
			popped = r
	var hn := chunk.get_node_or_null("Batch_" + NightAtmos.HALO_KEY) as MultiMeshInstance3D
	var sn := chunk.get_node_or_null("Batch_" + NightAtmos.SHAFT_KEY) as MultiMeshInstance3D
	var gn := chunk.get_node_or_null("Batch_" + NightAtmos.SHOP_KEY) as MultiMeshInstance3D
	_t._check(lamps > 4 and with_halo == lamps and with_shaft == lamps and hn != null and hn.multimesh.instance_count >= lights,
		"every downtown lamp carries its halos and its shaft in its own prop record (%d lamps, %d halos)" % [lamps, lights])
	_t._check(hn != null and sn != null and hn.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and sn.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and chunk.get_node_or_null("BatchShadow_" + NightAtmos.HALO_KEY) == null and sn.visibility_range_end > 0.0,
		"halos and shafts are one shadowless batch each, the shafts with a draw distance")
	var shops := 0
	for c in chunk.get_children():
		if c is Building:
			shops += (c as Building).shop_pools.size()
	_t._check(shops == 0 or (gn != null and gn.multimesh.instance_count == shops), "a glow for every lit shop front (%d)" % shops)
	if not popped.is_empty():
		PropBreak.lamp_out(chunk, popped)
		_t._check(popped.get("out", false), "a popped lamp is out (its halo and shaft, glow keys, hidden with its pool)")
	var ids := _records(chunk)
	chunk.queue_free()
	NightAtmos.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	var ids_off := _records(off)
	var none := off.get_node_or_null("Batch_" + NightAtmos.HALO_KEY) == null and off.get_node_or_null("Batch_" + NightAtmos.SHAFT_KEY) == null \
		and off.get_node_or_null("Batch_" + NightAtmos.SHOP_KEY) == null
	off.queue_free()
	NightAtmos.enabled = true
	_t._check(none and ids == ids_off, "with NIGHT_ATMOS=0 the chunk has no atmosphere batches and every prop keeps its id and place (%d props)" % ids.size())


func _node(city: Node3D) -> void:
	# The city's own node when it is there (the chunks made it), else one staged for the checks.
	var node: NightAtmos = NightAtmos._node
	var staged := false
	if node == null or node.get_parent() != city:
		node = NightAtmos.new()
		staged = true
		city.add_child(node)
	var weather := city.get_node_or_null("Weather")
	var state_was := -1
	var forced_was := false
	var saved := {}
	if weather:
		state_was = int(weather.state)
		forced_was = bool(weather._forced)
		for k: String in ["state", "_previous", "blend", "wetness", "_timer"]:
			saved[k] = weather.get(k)
		weather.force_state(2)
	node._push()
	var g: Vector4 = node.pushed
	_t._check(weather == null or (node.haze >= 0.75 and absf(g.x - node.haze) < 1e-4 and g.w >= 64.0),
		"the node pushes a rainy night's haze to the global (%.2f, viewport %d px)" % [g.x, int(g.w)])
	if weather:
		weather.force_state(state_was)
		weather._forced = forced_was
		for k: String in saved:
			weather.set(k, saved[k])
	node._push()
	# The fog lean starts from DayNight / Weather's value each frame and never piles up.
	var env := Environment.new()
	env.fog_light_color = Color(0.2, 0.25, 0.3)
	env.fog_density = 0.0002
	var lamp_was := DayNight.lamp_now
	var haze_was := node.haze
	DayNight.lamp_now = 1.0
	node.haze = 0.9
	node.cam_height_override = 2.0
	node._env = env
	node._sodium()
	var c1 := env.fog_light_color
	var d1 := env.fog_density
	node._sodium()
	var c2 := env.fog_light_color
	env.fog_light_color = Color(0.2, 0.25, 0.3)
	env.fog_density = 0.0002
	node._sodium()
	_t._check(c1.r > 0.3 and c1.is_equal_approx(c2) and env.fog_light_color.is_equal_approx(c1) and d1 > 0.0002 and is_equal_approx(env.fog_density, d1),
		"the canyon's sodium haze leans the fog toward sodium without piling up frame to frame (r %.2f)" % c1.r)
	DayNight.lamp_now = lamp_was
	node.haze = haze_was
	node.cam_height_override = -1.0
	node._env = null
	node._push()
	if staged:
		node.queue_free()

