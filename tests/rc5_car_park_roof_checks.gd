extends RefCounted
## The car park's roof deck at 18:15 (RcCarParkRoof, the car_park_roof reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the parked cars' paint is a real car park's mix (mostly neutrals, some metallic, the same
## stall the same car every time); the core's face, the parapets and the poles build into their
## own surfaces without adding collision except the poles' pedestals, one pole where the old roof
## had one; the deck shader's roof pass and the paint's metallic are guarded (0 = as before); the
## camera row stands on a car park's roof, inside its footprint, at eye height.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	_paints()
	_geometry()
	_shaders()
	_camera(plan)


func _paints() -> void:
	var n := 3000
	var neutral := 0
	var saturated := 0
	var metal := 0
	var same := true
	for i in n:
		var parts := [1337, i % 6, i % 5, i]
		var p: Array = RcCarParkRoof.paint(parts)
		var idx := Vehicle.PAINTS.find(p[0])
		if idx >= 0 and idx < RcCarParkRoof.NEUTRAL_END:
			neutral += 1
		elif idx >= RcCarParkRoof.MUTED_END:
			saturated += 1
		if p[1]:
			metal += 1
		if i < 50 and RcCarParkRoof.paint(parts) != p:
			same = false
	var ns := float(neutral) / float(n)
	var ss := float(saturated) / float(n)
	_t._check(ns > 0.74 and ns < 0.86 and ss > 0.04 and ss < 0.12 and metal > n / 6 and same,
		"car park paint: a real car park's mix (%.0f %% neutral, %.0f %% saturated, %d of %d metallic), one car a stall" % [ns * 100.0, ss * 100.0, metal, n])


func _layout() -> Dictionary:
	return CarPark.layout(72.4, 61.3, 5)


func _geometry() -> void:
	var lay := _layout()
	var g := CarParkBuild.Geo.new()
	RcCarParkRoof.core(g, lay, "band_5")
	RcCarParkRoof.parapets(g, lay)
	var col_after_dress := g.col.size()
	RcCarParkRoof.poles(g, lay)
	g.commit()
	var has := func(key: String) -> bool:
		return (g._s as Dictionary).has(key)
	_t._check(col_after_dress == 0 and g.col.size() > 0 and has.call("rc5_joint") and has.call("rc5_pole")
			and has.call("rc5_pedestal") and has.call("rc5_head") and has.call("band_5") and has.call("coping"),
		"car park roof: the core, parapets and poles build (no collision but the pedestals; %d collision verts)" % g.col.size())
	# One pole where the old roof had one, as tall as it plus its pedestal, inside the aisles.
	var old := CarParkBuild.Geo.new()
	CarParkBuild._roof(old, lay)
	var ped := (g._s["rc5_pedestal"] as CarParkBuild.CpSurf).v
	var old_haz := (old._s["hazard"] as CarParkBuild.CpSurf).v
	var top := -1e9
	for p: Vector3 in (g._s["rc5_pole"] as CarParkBuild.CpSurf).v:
		top = maxf(top, p.y)
	var roof := CarPark.FLOOR * float(lay.decks)
	# A pedestal is 12 facets x 3 triangles (108 vertices); the old foot a box of 36 vertices.
	_t._check(ped.size() / 108 == old_haz.size() / 36 and absf(top - (roof + RcCarParkRoof.PEDESTAL + RcCarParkRoof.POLE_H)) < 0.01,
		"car park roof: one pole for each old one (%d), %.1f m over the deck" % [ped.size() / 108, top - roof])


func _shaders() -> void:
	var deck: String = (load("res://shaders/car_park_deck.gdshader") as Shader).code
	var inc := FileAccess.get_file_as_string("res://shaders/car_paint.gdshaderinc")
	var mat := CarParkBuild.material("deck") as ShaderMaterial
	_t._check(deck.contains("uniform float rc5 = 0.0;") and deck.contains("if (roof && rc5 > 0.5)")
			and inc.contains("inst_metal = INSTANCE_CUSTOM.a > 1.5 ? 1.0 : 0.0;")
			and float(mat.get_shader_parameter("rc5")) == (1.0 if RcCarParkRoof.enabled else 0.0),
		"car park roof: the deck's roof pass and the parked cars' metallic are guarded (0 = as before)")


func _camera(plan: CityPlan) -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if table is Dictionary:
		for c: Dictionary in table.get("cameras", []):
			if String(c.get("name", "")) == "car_park_roof":
				row = c
	if row.is_empty() or plan == null or plan.macro == null:
		_t._check(false, "car park roof: the camera row car_park_roof is in cameras_w8.json")
		return
	var eye: Array = row.eye
	var at := Vector2(float(eye[0]), float(eye[2]))
	var s := CarPark.nearest(plan, at, 200.0)
	var ok := false
	var msg := "no car park"
	if not s.is_empty():
		var lay: Dictionary = s.layout
		var f: Dictionary = s.frame
		var o := CarPark.world_xz(s, float(lay.u0), float(lay.v0))
		var d := at - o
		var u := d.dot(f.a)
		var v := d.dot(f.n)
		var roof := CarPark.ground_y(plan, s) + CarPark.FLOOR * float(lay.decks)
		var h := float(eye[1]) - roof
		ok = u > CarPark.CORE and u < float(lay.ls) and absf(v) < float(lay.ds) and h > 1.4 and h < 2.0 and not bool(row.get("agl", true))
		msg = "%s, u %.1f v %.1f, %.2f m over the roof" % [s.name, u, v, h]
	_t._check(ok, "car park roof: the camera stands on a car park's roof at eye height (%s)" % msg)
