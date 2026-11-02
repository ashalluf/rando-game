extends RefCounted
## The LA River from the bed (RiverLook, RiverDebris; the la_river reference camera in
## tools/refcams/cameras_w5.json; docs/HANDOFF.md "The LA River from the bed"), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The water's channel colour decodes to the river's cross direction, bed and bank; the mirror's
## model meets the bank at a grazing angle and the sky looking up, and its numbers are the shader's;
## the concrete keeps the old look under river_look 0; a FULL chunk at the 6th St bridge grows weeds
## and lays litter, and LOD lays none.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var rv: LaRiver = plan.macro.river if plan.macro else null
	if rv == null or not RiverLook.enabled():
		_t._check(true, "river look: off (no river or RIVER_LOOK=0), nothing to check")
		return
	_channel(rv)
	_mirror(rv)
	_shaders()
	_chunks(city, plan, rv)


func _channel(rv: LaRiver) -> void:
	var bad := 0
	var s := 100.0
	while s < rv.length - 100.0:
		var c := RiverLook.water_color(rv, s)
		var lat := Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0)
		var d: Vector2 = rv.at(s)[1]
		if absf(lat.length() - 1.0) > 0.02 or absf(lat.dot(d)) > 0.02 or absf(c.b * 40.0 - rv.bed_half(s)) > 0.01 \
				or absf(c.a * 10.0 - rv.depth(s)) > 0.01:
			bad += 1
		s += 250.0
	_t._check(bad == 0, "river look: the water's colour is the cross direction, the bed's half width and the bank's height (%d bad)" % bad)


func _mirror(rv: LaRiver) -> void:
	var s := 2400.0
	var c := RiverLook.water_color(rv, s)
	var lat := Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0)
	var bh := rv.bed_half(s)
	var dep := rv.depth(s)
	var across := Vector3(lat.x, 0.0, lat.y)
	var graze := RiverLook.mirror_hit((across + Vector3.UP * 0.05).normalized(), 0.0, lat, bh, dep)
	var other := RiverLook.mirror_hit((-across + Vector3.UP * 0.05).normalized(), 0.0, lat, bh, dep)
	var up := RiverLook.mirror_hit((across * 0.2 + Vector3.UP).normalized(), 0.0, lat, bh, dep)
	var d: Vector2 = rv.at(s)[1]
	var down_river := RiverLook.mirror_hit((Vector3(d.x, 0.0, d.y) + Vector3.UP * 0.02).normalized(), 0.0, lat, bh, dep)
	_t._check(graze == 0 and other == 0 and up == 2 and down_river == 2,
		"river look: a grazing ray across meets the bank (%d, %d), one up or down the river the sky (%d, %d)" % [graze, other, up, down_river])


func _shaders() -> void:
	var water := FileAccess.get_file_as_string("res://shaders/river_water.gdshader")
	var slope := _const(water, "RW_SLOPE")
	var toe := _const(water, "RW_TOE")
	_t._check(absf(slope - LaRiver.SLOPE) < 0.001 and absf(toe - RiverLook.toe_over_water()) < 0.005,
		"river look: the water shader's bank slope (%.2f) and toe (%.2f) are LaRiver's" % [slope, toe])
	var concrete := FileAccess.get_file_as_string("res://shaders/river_concrete.gdshader")
	_t._check(water.contains("if (river_look > 0.5)") and concrete.count("river_look > 0.5") >= 4,
		"river look: every new branch of the river's shaders is behind river_look (the A/B)")


func _const(src: String, name: String) -> float:
	var re := RegEx.create_from_string("const float " + name + " = ([0-9.]+);")
	var m := re.search(src)
	return m.get_string(1).to_float() if m else -1.0


func _chunks(city: Node3D, plan: CityPlan, rv: LaRiver) -> void:
	var k := Vector2i(9999, 9999)
	for br: Dictionary in rv.bridges(plan):
		if br.name == "6TH ST":
			k = br.owner
	if k == Vector2i(9999, 9999):
		_t._check(true, "river look: no 6th St bridge on this seed")
		return
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var got: Vector2i = chunk.get_meta("rv_debris", Vector2i(-1, -1))
	var tufts := chunk.get_node_or_null("Batch_rv_tuft_0") != null or chunk.get_node_or_null("Batch_rv_tuft_1") != null
	_t._check(got.x > 40 and got.x <= RiverDebris.MAX_WEEDS and got.y <= RiverDebris.MAX_LITTER and tufts,
		"river look: the 6th St chunk %s grows %d weed spots and lays %d pieces of litter" % [k, got.x, got.y])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var none := not lod.has_meta("rv_debris") and lod.get_node_or_null("Batch_rv_tuft_0") == null
	lod.get_parent().remove_child(lod)
	lod.free()
	_t._check(none, "river look: an LOD chunk lays no weeds or litter")
