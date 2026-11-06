extends RefCounted
## The suburb refcam's fixes (wave 5, rc2-suburb; RcSuburb), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Residents' cars: a pure hash per kerb stall at about RESIDENT_ODDS, only in the residential
## districts, none with the switch off; a suburb block built with them keeps every car it parked
## without them and parks more, never two cars on one stall. The DG yard and the leaf dither: the
## shader uniforms exist and the materials carry the switch. Each block build is freed with its cars.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_t._check(false, "rc2_suburb: the city has a plan")
		return
	_rolls(plan)
	_shaders()
	_kerbs(city, plan)


func _rolls(plan: CityPlan) -> void:
	var s := [Vector3(10.0, 0.4, 20.0), 0.0, 1.0]
	_t._check(RcSuburb.resident_roll(plan.seed, s) == RcSuburb.resident_roll(plan.seed, s.duplicate()),
		"RcSuburb: a resident's car is a pure hash of the stall")
	var hits := 0
	var same := 0
	for i in 600:
		var spot := [Vector3(float(i) * 8.0, 0.4, 53.0), 0.0, 1.0]
		var a := RcSuburb.resident_roll(plan.seed, spot)
		hits += 1 if a else 0
		same += 1 if a and BusyStreets.park_extra_roll(plan.seed, spot) else 0
	_t._check(absf(hits / 600.0 - RcSuburb.RESIDENT_ODDS) < 0.06, "RcSuburb: residents take about %.0f %% of the stalls (%d of 600)" % [RcSuburb.RESIDENT_ODDS * 100.0, hits])
	_t._check(same < hits / 3, "RcSuburb: the residents' roll is not BusyStreets' (%d of %d shared)" % [same, hits])
	var was := RcSuburb.enabled
	_t._check(RcSuburb.residential(CityPlan.District.SUBURBS) and RcSuburb.residential(CityPlan.District.BEACHTOWN)
		and not RcSuburb.residential(CityPlan.District.DOWNTOWN) and not RcSuburb.residential(CityPlan.District.INDUSTRIAL),
		"RcSuburb: residents park in the suburbs and the beach town only")
	RcSuburb.enabled = false
	_t._check(not RcSuburb.residential(CityPlan.District.SUBURBS), "RcSuburb: RC2_SUBURB=0 parks no residents")
	RcSuburb.enabled = was


func _shaders() -> void:
	var yard := FileAccess.get_file_as_string("res://shaders/lot_yard.gdshader")
	_t._check(yard.contains("uniform float dg_real") and yard.contains("dg_real > 0.5"), "RcSuburb: lot_yard draws the pale DG behind dg_real")
	var tree := FileAccess.get_file_as_string("res://shaders/la_tree.gdshader")
	_t._check(tree.contains("uniform float sprig_dither_fix") and tree.contains("RENDERER_COMPATIBILITY") and tree.contains("hash_px("),
		"RcSuburb: la_tree's Compatibility leaf dither waits for a sub-pixel leaf")
	var m: ShaderMaterial = YardFill.yard_material()
	_t._check(is_equal_approx(float(m.get_shader_parameter("dg_real")), 1.0 if RcSuburb.enabled else 0.0), "RcSuburb: the yard material carries the switch")
	var lt: ShaderMaterial = LaTrees.material(LaTrees.Species.OLIVE)
	_t._check(is_equal_approx(float(lt.get_shader_parameter("sprig_dither_fix")), 1.0 if RcSuburb.enabled else 0.0), "RcSuburb: the LA trees' material carries the switch")


func _kerbs(city: Node3D, plan: CityPlan) -> void:
	# A suburb block (the refcam's own: Valley side, x ~2000, z ~4300).
	var k := plan.block_index_at(Vector2(2050.0, 4300.0))
	var b := plan.block(k.x, k.y)
	if int(b.district) != CityPlan.District.SUBURBS or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
		_t._check(false, "rc2_suburb: the refcam's block %s is a suburb buildings block" % str(k))
		return
	var saved_budget := PhysicsBudget.max_active_bodies
	PhysicsBudget.max_active_bodies = PhysicsBudget.active_body_count() + 400
	var was := RcSuburb.enabled
	RcSuburb.enabled = false
	var bare := _cars_of(city, k)
	RcSuburb.enabled = true
	var full := _cars_of(city, k)
	RcSuburb.enabled = was
	PhysicsBudget.max_active_bodies = saved_budget
	var kept := true
	for c: String in bare.cars:
		kept = kept and full.cars.has(c)
	_t._check(kept, "RcSuburb: the block keeps every car it parked without the residents (%d)" % bare.cars.size())
	_t._check(full.residents > 0 and bare.residents == 0, "RcSuburb: residents park on the suburb block (%d, %d with the switch off)" % [full.residents, bare.residents])
	var spots := {}
	var doubled := 0
	for c: String in full.cars:
		var key := c.get_slice(" ", 1) + " " + c.get_slice(" ", 2)
		doubled += 1 if spots.has(key) else 0
		spots[key] = true
	_t._check(doubled == 0, "RcSuburb: never two cars on one stall (%d doubled of %d)" % [doubled, full.cars.size()])


## The block built FULL alone: its cars as "type x z" and how many are residents'; the build and
## every car it parked freed (they live under the city root).
func _cars_of(city: Node3D, k: Vector2i) -> Dictionary:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var out: Array = []
	var residents := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("%d %.1f %.1f" % [int((car as Vehicle).body_type), p.x, p.z])
			residents += 1 if (car as Node).has_meta("rc2_resident") else 0
			(car as Node).queue_free()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	return {"cars": out, "residents": residents}
