extends RefCounted
## The suburb_night refcam's fixes (wave 8, rc5-suburb-night; SuburbMoon, SuburbNight), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The moon: a pure gain, MOON_GAIN deep in the night over a residential place, 1 by day, at dusk,
## downtown and with the switch off; the refcam's eye is residential. The window spill: the
## refcam's suburb block built FULL with it off and on keeps every other batch's count and every
## prop, and on lays a spill a ground-floor room pane; the shaders and materials carry the switch.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_t._check(false, "rc5_suburb_night: the city has a plan")
		return
	_moon(plan)
	_shaders()
	_spill(city, plan)


func _moon(plan: CityPlan) -> void:
	var was := SuburbMoon.enabled
	SuburbMoon.enabled = true
	_t._check(is_equal_approx(SuburbMoon.gain_for(1.0, 1.0), SuburbMoon.MOON_GAIN), "SuburbMoon: a residential street at full night has %.2f of the moon" % SuburbMoon.MOON_GAIN)
	_t._check(is_equal_approx(SuburbMoon.gain_for(1.0, 0.5), 1.0) and is_equal_approx(SuburbMoon.gain_for(1.0, 0.0), 1.0),
		"SuburbMoon: the day, the sunset and the blue hour keep the whole moon")
	_t._check(is_equal_approx(SuburbMoon.gain_for(0.0, 1.0), 1.0), "SuburbMoon: a street that is not residential keeps the whole moon")
	var eye := Vector2(1979.0, 4256.8)
	_t._check(SuburbMoon.residential(plan, eye) > 0.9, "SuburbMoon: the suburb_night refcam's eye is residential (%.2f)" % SuburbMoon.residential(plan, eye))
	_t._check(SuburbMoon.residential(plan, Vector2(2800.0, 100.0)) == 0.0, "SuburbMoon: Pershing Square is not residential")
	SuburbMoon.enabled = false
	_t._check(is_equal_approx(SuburbMoon.gain_for(1.0, 1.0), 1.0), "SuburbMoon: SUBURB_NIGHT=0 keeps the whole moon")
	SuburbMoon.enabled = was


func _shaders() -> void:
	var glow := FileAccess.get_file_as_string("res://shaders/house_glow.gdshader")
	_t._check(glow.contains("uniform float suburb_night") and glow.contains("shape == 2 && suburb_night > 0.5"),
		"SuburbNight: house_glow draws the lantern's point-source wash behind suburb_night")
	var lamp := FileAccess.get_file_as_string("res://shaders/house_lamp.gdshader")
	_t._check(lamp.contains("uniform float suburb_night") and lamp.contains("suburb_night > 0.5"),
		"SuburbNight: house_lamp draws the lantern's panes and bulb behind suburb_night")
	var spill := FileAccess.get_file_as_string("res://shaders/suburb_spill.gdshader")
	_t._check(spill.contains("house_nights.gdshaderinc") and spill.contains("hn_share(key, city_hour)") and spill.contains("/ 255.0")
		and spill.contains("fog_disabled"), "SuburbNight: the spill reads the pane's lit roll from HouseNights' hash (8-bit roll, fog off)")
	var on := 1.0 if SuburbNight.enabled else 0.0
	var gm: ShaderMaterial = HouseNights.glow_mesh(2).material
	_t._check(is_equal_approx(float(gm.get_shader_parameter("suburb_night")), on), "SuburbNight: the scallop material carries the switch")
	_t._check(is_equal_approx(float(HouseNights.lamp_material().get_shader_parameter("suburb_night")), on), "SuburbNight: the lamp material carries the switch")
	# The pane's roll as an 8-bit vertex colour: exact, and the fixed door / garage rolls throw nothing.
	var exact := true
	for i in 256:
		exact = exact and SuburbNight.pane_q(float(i) / 255.0) == i
	_t._check(exact, "SuburbNight: a pane's roll survives as its 8-bit vertex alpha")


func _spill(city: Node3D, plan: CityPlan) -> void:
	# The refcam's suburb block (rc2-suburb's: Valley side, x ~2000, z ~4300).
	var k := plan.block_index_at(Vector2(2050.0, 4300.0))
	var b := plan.block(k.x, k.y)
	if int(b.district) != CityPlan.District.SUBURBS:
		_t._check(false, "rc5_suburb_night: the refcam's block %s is a suburb" % str(k))
		return
	var saved_budget := PhysicsBudget.max_active_bodies
	PhysicsBudget.max_active_bodies = PhysicsBudget.active_body_count() + 400
	var was := SuburbNight.enabled
	SuburbNight.enabled = false
	var bare := _batches_of(city, k)
	SuburbNight.enabled = true
	var full := _batches_of(city, k)
	SuburbNight.enabled = was
	PhysicsBudget.max_active_bodies = saved_budget
	var same := true
	var diff := ""
	for key: String in bare.counts:
		if int(full.counts.get(key, -1)) != int(bare.counts[key]):
			same = false
			diff += " %s %d/%d" % [key, int(bare.counts[key]), int(full.counts.get(key, -1))]
	for key: String in full.counts:
		if key != "Batch_" + SuburbNight.SPILL_KEY and not bare.counts.has(key):
			same = false
			diff += " +" + key
	_t._check(same, "SuburbNight: every other batch of the block is the same with the spill on%s" % diff)
	_t._check(bare.props == full.props, "SuburbNight: the block's props are the same with the spill on (%d)" % bare.props)
	var spills := int(full.counts.get("Batch_" + SuburbNight.SPILL_KEY, 0))
	_t._check(spills > 4 and not bare.counts.has("Batch_" + SuburbNight.SPILL_KEY),
		"SuburbNight: the suburb block lays its window spills (%d), none with the switch off" % spills)
	_t._check(full.spill_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "SuburbNight: the spill casts no shadow")


## The block built FULL alone: its batches' instance counts, its prop count, the spill's shadow
## setting; the build and every car it parked freed (they live under the city root).
func _batches_of(city: Node3D, k: Vector2i) -> Dictionary:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var counts := {}
	var shadow := -1
	for n in chunk.find_children("Batch_*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if mmi.multimesh:
			counts[String(mmi.name)] = int(counts.get(String(mmi.name), 0)) + mmi.multimesh.instance_count
		if String(mmi.name) == "Batch_" + SuburbNight.SPILL_KEY:
			shadow = mmi.cast_shadow
	var props: int = (chunk.get("prop_records") as Array).size() if chunk.get("prop_records") is Array else -1
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).queue_free()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	return {"counts": counts, "props": props, "spill_shadow": shadow}
