extends RefCounted
## The crowd plaza refcam's fixes (wave 5, rc2-crowd-plaza), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## PlazaCrowd: a plaza's head-count follows the hour and its area, strips keep theirs, open-ground
## targets fall inside the plaza, the dealt rigs spread evenly and never repeat a rig and a look,
## the switch gives the old crowd back. CrowdDress: one look is many outfits across the rigs, a
## quarter of the looks plain, the switch gives the old rolls back. Pure: nothing here leans on
## what an earlier check left.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	_counts()
	_targets()
	_deal()
	_dress()
	_tame()


func _counts() -> void:
	var plaza := Rect2(Vector2(2130.0, 1066.8), Vector2(56.0, 70.3))
	var strip := Rect2(Vector2(3407.0, -1661.7), Vector2(15.0 - 2.0, 246.0))
	_t._check(PlazaCrowd.is_open(plaza) and not PlazaCrowd.is_open(strip), "PlazaCrowd: a 56 x 70 m plaza is open ground, a 13 m strip is not")
	var lunch := PlazaCrowd.count(plaza, 46, 12.5)
	var night := PlazaCrowd.count(plaza, 46, 3.0)
	_t._check(lunch >= 110 and lunch <= floori(plaza.get_area() / PlazaCrowd.AREA_PER_PERSON),
		"PlazaCrowd: STARLIGHT PLAZA at 12:30 holds %d people (wanted 110+, under one a %.0f m2)" % [lunch, PlazaCrowd.AREA_PER_PERSON])
	_t._check(night < 46 and night >= 1, "PlazaCrowd: the plaza at 03:00 is quieter than its old count (%d)" % night)
	_t._check(PlazaCrowd.count(strip, 16, 12.5) == 16, "PlazaCrowd: a strip keeps its own count at any hour")
	var small := Rect2(Vector2.ZERO, Vector2(20.0, 20.0))
	_t._check(PlazaCrowd.count(small, 40, 13.0) <= maxi(40, floori(400.0 / PlazaCrowd.AREA_PER_PERSON)),
		"PlazaCrowd: a small plaza is never packed past its area")
	var was := PlazaCrowd.enabled
	PlazaCrowd.enabled = false
	var off := PlazaCrowd.count(plaza, 46, 12.5)
	PlazaCrowd.enabled = was
	_t._check(off == 46, "PLAZA_CROWD=0 keeps the landmark's own count (%d)" % off)


func _targets() -> void:
	var ped := Pedestrian.new()
	ped.setup(Rect2(Vector2(100.0, 200.0), Vector2(40.0, 60.0)), 20.0, 1234)
	ped.open_ground = true
	var inside := true
	var mid := 0
	for i in 200:
		var p := ped._random_ring_point(20.0)
		inside = inside and Rect2(Vector2(100.0, 200.0), Vector2(40.0, 60.0)).has_point(p)
		if absf(p.x - 120.0) < 10.0 and absf(p.y - 230.0) < 15.0:
			mid += 1
	_t._check(inside, "PlazaCrowd: open-ground targets fall inside the plaza")
	_t._check(mid >= 25, "PlazaCrowd: the middle of the plaza is somewhere people go (%d of 200 in the middle quarter)" % mid)
	_t._check(ped._ring_route(Vector2(102.0, 202.0), Vector2(138.0, 258.0)).is_empty(),
		"PlazaCrowd: a plaza walker crosses straight, not round the corners")
	ped.open_ground = false
	_t._check(not ped._ring_route(Vector2(102.0, 202.0), Vector2(138.0, 258.0)).is_empty(),
		"a pavement walker still goes round the corners")
	ped.free()


func _deal() -> void:
	var chunk := Node3D.new()
	var rect := Rect2(Vector2(2130.0, 1066.8), Vector2(56.0, 70.3))
	var models := ["a", "b", "c", "d", "e", "f", "g"]
	var seen := {}
	var per_model := {}
	var twins := 0
	for i in models.size() * 3:
		var ped := Pedestrian.new()
		ped.ring = rect
		ped.open_ground = true
		chunk.add_child(ped)
		var d: Array = PlazaCrowd.deal(ped, models)
		if d.size() != 2:
			_t._check(false, "PlazaCrowd.deal gives a rig and a look")
			chunk.free()
			return
		var k := "%s|%d" % [d[0], int(d[1])]
		twins += 1 if seen.has(k) else 0
		seen[k] = true
		per_model[d[0]] = int(per_model.get(d[0], 0)) + 1
	var even := true
	for m: String in models:
		even = even and int(per_model.get(m, 0)) == 3
	_t._check(even, "PlazaCrowd: 21 walkers on a plaza take each of 7 rigs three times (%s)" % str(per_model))
	_t._check(twins == 0, "PlazaCrowd: no two walkers on a plaza share a rig and a look (%d)" % twins)
	var ped2 := Pedestrian.new()
	ped2.ring = rect
	chunk.add_child(ped2)
	_t._check(PlazaCrowd.deal(ped2, models).is_empty(), "PlazaCrowd: a pavement walker rolls its own rig")
	chunk.free()


func _dress() -> void:
	# A crowd rig's texture by name: the seed is the look and the rig's file.
	var a := ImageTexture.new()
	a.resource_path = "res://rc2_check/crowd_a_body.jpg"
	var b := ImageTexture.new()
	b.resource_path = "res://rc2_check/crowd_b_body.jpg"
	var differs := 0
	for look in 24:
		if CrowdDress.look_seed(a, look, true) != CrowdDress.look_seed(b, look, true):
			differs += 1
	_t._check(differs == 24, "CrowdDress: the same look on two rigs is two outfits (%d of 24 looks differ)" % differs)
	_t._check(CrowdDress.look_seed(a, 5, false) == 4205, "CrowdDress: a rig without region masks keeps the old roll")
	var plain := 0
	for look in 24:
		plain += 1 if CrowdDress.plain(look, true) else 0
	_t._check(plain == 6, "CrowdDress: a quarter of the looks keep the rig's own outfit (%d)" % plain)
	var was := CrowdDress.enabled
	CrowdDress.enabled = false
	var old_ok := CrowdDress.look_seed(a, 7, true) == 4207 and CrowdDress.plain(4, true) and not CrowdDress.plain(5, true)
	CrowdDress.enabled = was
	_t._check(old_ok, "CROWD_DRESS=0 gives the old rolls back")


func _tame() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	mat.set_shader_parameter("cloth_sat", 0.8)
	mat.set_shader_parameter("pants_sat", 0.2)
	CrowdDress.tame(mat, true)
	_t._check(float(mat.get_shader_parameter("cloth_sat")) <= CrowdDress.SAT_MAX + 0.001 and float(mat.get_shader_parameter("pants_sat")) < 0.2,
		"CrowdDress: a bright top is muted, a dull one kept dull")
	mat.set_shader_parameter("cloth_sat", 0.8)
	CrowdDress.tame(mat, false)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("cloth_sat")), 0.8), "CrowdDress: a rig without region masks keeps its colours")
