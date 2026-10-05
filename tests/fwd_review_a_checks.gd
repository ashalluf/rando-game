extends RefCounted
## The Forward+ review A fixes (docs/HANDOFF.md "Forward+ review A"), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The canals' water: every canal's pieces tile its band exactly (no gap, no overlap), and every
## crossing is a piece of its own on the north-south canal, tagged with the east-west one (the
## shader mirrors down the canal the ray runs along there). The canal shader reads the crossing tag
## and decodes sky_tint. The pier's light pools wear their own, dimmer copy of the pool material.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var lay := Canals.layout(plan)
	if not lay.is_empty():
		_canal_water(lay)
	var src := FileAccess.get_file_as_string("res://shaders/canal_water.gdshader")
	_t._check(src.contains("cs_srgb_to_linear(sky_tint.rgb)") and src.contains("axis > 1.5"),
		"the canal water decodes sky_tint and mirrors a crossing down either canal")
	_t._check(PierPark.POOL_STRENGTH < 1.0 and PierPark.POOL_FALLOFF > 1.3,
		"the pier's light pools are dimmer and softer than the street lamps' (%.2f, %.2f)" % [PierPark.POOL_STRENGTH, PierPark.POOL_FALLOFF])


func _canal_water(lay: Dictionary) -> void:
	var canals: Array = lay.canals
	var half := Canals.BED_HALF + 1.6
	var bad_area := 0
	var crossings := 0
	var expected := 0
	for ci in canals.size():
		var c: Dictionary = canals[ci]
		var split: Array = Canals.water_pieces(canals, ci, half)
		var pieces: Array = split[0]
		var cross: Array = split[1]
		var area := 0.0
		for i in pieces.size():
			var r: Rect2 = pieces[i]
			area += r.get_area()
			for j in range(i + 1, pieces.size()):
				var o: Rect2 = r.intersection(pieces[j])
				if o.size.x > 0.01 and o.size.y > 0.01:
					bad_area += 1
			if int(cross[i]) >= 0:
				crossings += 1
				if int(canals[int(cross[i])].axis) == int(c.axis):
					bad_area += 1
		var band := Canals._canal_rect(c, half).get_area()
		if absf(area - band) > band * 0.001:
			bad_area += 1
		if int(c.axis) == 0:
			for o: Dictionary in canals:
				if int(o.axis) == 1 and Canals._canal_rect(c, half).intersects(Canals._canal_rect(o, half)):
					expected += 1
	_t._check(bad_area == 0 and crossings == expected and crossings > 0,
		"every canal's water tiles its band, each crossing its own piece tagged with the cross canal (%d crossings, %d bad)" % [crossings, bad_area])
