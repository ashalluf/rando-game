extends Node
func _ready() -> void:
	var city: Node3D = load("res://scenes/levels/city.tscn").instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 5:
		await get_tree().physics_frame
	var plan: CityPlan = city.plan
	var k := plan.block_index_at(Vector2(589.0, 860.0))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.begin_build()
	var names := []
	for s in chunk._steps:
		names.append(s.get_method())
	printerr("steps ", names)
	while chunk._step < chunk._steps.size() - 1:
		chunk.build_step()
	var parts := StreetWear._ground_parts(chunk)
	printerr("parts ", parts.size(), " buildings ", chunk.building_count, " props ", chunk.prop_records.size(), " enabled ", StreetWear.enabled, " level ", chunk.level, " zone ", chunk.zone)
	printerr("meta ", chunk.get_meta("street_wear", null))
	printerr("wear n ", chunk._batch.data()["wear"].xforms.size() if chunk._batch.data().has("wear") else 0)
	for d in [[0,0],[1,0],[0,1],[-1,0],[3,1],[-2,0],[-3,1],[1,-1],[2,-2]]:
		var c2: CityChunk = city._new_chunk(k + Vector2i(d[0], d[1]), CityChunk.Level.FULL)
		c2.begin_build()
		while c2._step < c2._steps.size() - 1:
			c2.build_step()
		var modes := [0,0,0,0]
		if c2._batch.data().has("wear"):
			for cu: Color in c2._batch.data()["wear"].custom:
				modes[int(cu.r / 100.0)] += 1
		printerr("  modes tag/buff/poster/sticker ", modes, " parts ", StreetWear._ground_parts(c2).size())
		c2._finish_build()
		var b = plan.block(c2.ix, c2.iz)
		printerr(c2.key, " district ", b.district, " kind ", b.kind, " buildings ", c2.building_count, " parts ", 0, " wear ", (c2.get_meta("street_wear") as PackedVector2Array).size())
	get_tree().quit()
