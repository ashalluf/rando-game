extends RefCounted
## The Chinatown refcam (Rc3Chinatown, the chinatown_dusk camera in tools/refcams/cameras_w6.json),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the shader carries the traced shop room, the lantern silk and the hall's lit screens, all
## behind `rc3` (0 = the old branches untouched); the material takes rc3 and the lacquer wash from
## the switch; the lanterns are round enough with it on and as before with it off; the hall's lattice
## carries the lit flag (and nothing that sways does), and the A/B builds the old hall; the plaza's
## masts are round posts with it on.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	var was := Rc3Chinatown.enabled
	_shader()
	Rc3Chinatown.enabled = true
	_material(true)
	var on := _lantern_tris()
	var hall_on := _hall()
	Rc3Chinatown.enabled = false
	_material(false)
	var off := _lantern_tris()
	var hall_off := _hall()
	Rc3Chinatown.enabled = was
	_material(was)
	_t._check(off == 116 and on > off and on <= 180, "a lantern is %d triangles with the refcam's sides, %d without (was 116)" % [on, off])
	_t._check(int(hall_on.lit) >= 20 and int(hall_on.sway_lit) == 0, "the hall's screens carry the lit flag (%d faces), nothing that sways does" % int(hall_on.lit))
	_t._check(int(hall_off.lit) == 0 and int(hall_off.shop) > 0, "the A/B builds the hall as before (no lit flag, its shop-glass door)")
	_t._check(int(hall_on.shop) == 0, "with the refcam the hall's door is a lit screen, not shop glass")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/chinatown.gdshader")
	_t._check(src.contains("uniform float rc3 = 0.0;") and src.contains("vec4 shop_room(") and src.contains("uniform float lacquer_wash = 1.0;"),
		"the Chinatown shader carries the traced shop room and the lacquer wash, both off by default")
	_t._check(src.contains("if (rc3 > 0.5) {") and src.count("rc3 > 0.5") >= 3, "the shop room, the silk and the hall's screens are each behind rc3")
	_t._check(src.contains("v_lit = (UV2.x < 0.0005 && UV2.y > 1.5)") and Rc3Chinatown.LIT_FLAG > 1.5,
		"the shader's lit flag is Rc3Chinatown.LIT_FLAG (%.1f) on a face that does not sway" % Rc3Chinatown.LIT_FLAG)


func _material(on: bool) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/chinatown.gdshader")
	Rc3Chinatown.apply(mat)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("rc3")), 1.0 if on else 0.0)
		and is_equal_approx(float(mat.get_shader_parameter("lacquer_wash")), Rc3Chinatown.LACQUER_WASH if on else 1.0),
		"the material's rc3 and lacquer wash follow the switch (%s)" % ("on" if on else "off"))
	Rc3Chinatown.apply(ChinatownKit.material())


func _lantern_tris() -> int:
	var g := ChinatownGeo.new()
	g.use(ChinatownKit.KEY, ChinatownKit.material())
	ChinatownKit.lantern(g, Vector3.ZERO, 0.1, 0.5, Color.RED, 0.0)
	return g.triangles


func _hall() -> Dictionary:
	var g := ChinatownGeo.new()
	g.use(ChinatownKit.KEY, ChinatownKit.material())
	g.fine = ChinatownGeo.new()
	g.fine.use(ChinatownKit.KEY, ChinatownKit.material())
	var st := {"geo": g, "shapes": []}
	ChinatownKit.hall_mesh(g, st, Transform3D.IDENTITY)
	var s: Dictionary = g._surfaces[ChinatownKit.KEY]
	var u2: PackedVector2Array = s.uv2
	var cols: PackedColorArray = s.col
	var lit := 0
	var sway_lit := 0
	var shop := 0
	var i := 0
	while i < u2.size():
		var kind := int(round(cols[i].a * 16.0))
		if u2[i].y > 1.5 and u2[i].x < 0.0005 and kind == ChinatownKit.K_LATTICE:
			lit += 1
		if u2[i].x > 0.001 and u2[i].y > 1.5:
			sway_lit += 1
		if kind == ChinatownKit.K_SHOP:
			shop += 1
		i += 3
	return {"lit": lit, "sway_lit": sway_lit, "shop": shop}
