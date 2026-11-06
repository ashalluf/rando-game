extends RefCounted
## The coast highway's beach houses as Malibu houses (CoastHouses), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Built into a bare Geo (CPU arrays: no renderer needed), every house of the stretch both ways
## (COAST_HOUSES on and off): the forms vary by hash (at least three on this seed) and follow the
## style; a two-storey modern sets its upper floor back over a terrace; every house has its glass
## wall to the sea, the plan's footprint (nothing past the eaves into the gap, the deck and stair
## where they were), collision for the slab, every storey and the deck; the cable rails stand on
## the timber houses; the plan itself does not depend on the switch.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var ch: CoastHighway = plan.macro.coast_highway if plan.macro else null
	if ch == null:
		_t._check(false, "coast houses: the stretch is planned")
		return
	_t._check(CoastHouses.enabled, "coast houses: on by default (COAST_HOUSES=0 is the A/B)")
	var forms := {}
	var setback_ok := true
	var cable_ok := true
	for hs: Dictionary in ch.houses:
		var f := CoastHouses.form(hs)
		forms[f] = int(forms.get(f, 0)) + 1
		var m := CoastHouses.massing(hs)
		var hw := (float(hs.z1) - float(hs.z0)) * 0.5
		if f == CoastHouses.Form.MODERN and int(hs.floors) == 2:
			if float(m.us) < CoastHouses.SETBACK.x - 0.01 or float(m.uz1) > float(hs.depth) - 2.0:
				setback_ok = false
		if float(m.ux0) < -hw - 0.001 or float(m.ux1) > hw + 0.001 or float(m.ux1) - float(m.ux0) < 5.0:
			setback_ok = false
		if int(hs.style) == CoastHighway.Style.CEDAR and not CoastHouses.cable_rails(hs):
			cable_ok = false
	_t._check(forms.size() >= 3, "coast houses: the forms vary by hash (%s of %d houses)" % [forms, ch.houses.size()])
	_t._check(setback_ok, "coast houses: the upper floors stay on the lot, a modern's set back from the sea over a terrace")
	_t._check(cable_ok, "coast houses: the cedar houses carry cable rails")

	var chunk := CityChunk.new()
	chunk.plan = plan
	chunk.level = CityChunk.Level.FULL
	var was := CoastHouses.enabled
	var stats_new := _build_all(chunk, ch, true)
	var stats_old := _build_all(chunk, ch, false)
	CoastHouses.enabled = was
	chunk.free()
	_t._check(int(stats_new.no_glass) == 0, "coast houses: every house has a glass wall to the sea (%d without)" % stats_new.no_glass)
	_t._check(int(stats_new.outside) == 0, "coast houses: nothing past a house's eaves into the gap or past its stair (%d vertices; worst %.2f m)" % [stats_new.outside, stats_new.worst])
	_t._check(int(stats_new.thin) == 0 and int(stats_new.boxes) >= int(stats_old.boxes) - ch.houses.size(),
		"coast houses: collision for the slab, every storey and the deck (%d boxes, the old house %d; %d short)" % [stats_new.boxes, stats_old.boxes, stats_new.thin])
	_t._check(int(stats_new.tris) > int(stats_old.tris) and int(stats_new.tris) < int(stats_old.tris) * 4,
		"coast houses: more modelled than the old house, within budget (%d triangles for %d houses, the old %d)" % [stats_new.tris, ch.houses.size(), stats_old.tris])
	# The plan is the plan whatever the switch: the same lots.
	var other := CoastHighway.new()
	other.build(plan.macro, ch.seed)
	var same := other.houses.size() == ch.houses.size()
	for i in mini(other.houses.size(), ch.houses.size()):
		if absf(float(other.houses[i].z0) - float(ch.houses[i].z0)) > 0.001 or int(other.houses[i].seed) != int(ch.houses[i].seed):
			same = false
	_t._check(same, "coast houses: the plan's lots and rolls are unchanged")


func _build_all(chunk: CityChunk, ch: CoastHighway, on: bool) -> Dictionary:
	CoastHouses.enabled = on
	var out := {"no_glass": 0, "outside": 0, "worst": 0.0, "boxes": 0, "thin": 0, "tris": 0}
	for hs: Dictionary in ch.houses:
		var g := CoastHighwayBuild.Geo.new()
		CoastHighwayBuild._house(chunk, ch, g, hs)
		var inv := CoastHighwayBuild._frame(ch, hs).affine_inverse()
		var hw := (float(hs.z1) - float(hs.z0)) * 0.5
		var far_z := float(hs.depth) + float(hs.deck) + 7.0
		var glass := 0
		var storeys := 0
		for key: String in g.s:
			var v: PackedVector3Array = g.s[key].v
			out.tris = int(out.tris) + v.size() / 3
			if key == "hh_glass":
				glass += v.size()
			for p: Vector3 in v:
				var l := inv * p
				var over := maxf(absf(l.x) - (hw + 0.66), maxf(-1.35 - l.z, l.z - far_z))
				if over > 0.0:
					out.outside = int(out.outside) + 1
					out.worst = maxf(float(out.worst), over)
		for bx: Array in g.boxes:
			var half: Vector3 = bx[1]
			if half.y > 1.2:
				storeys += 1
		out.boxes = int(out.boxes) + g.boxes.size()
		if on and glass == 0:
			out.no_glass = int(out.no_glass) + 1
		if storeys < int(hs.floors):
			out.thin = int(out.thin) + 1
	return out
